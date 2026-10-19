package com.limemall.item.service;

import cn.hutool.json.JSONUtil;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.stats.CacheStats;
import com.limemall.common.utils.BeanUtils;
import com.limemall.common.utils.CollUtils;
import com.limemall.item.config.CacheMqConfig;
import com.limemall.item.config.CacheProperties;
import com.limemall.item.domain.dto.ItemDTO;
import com.limemall.item.domain.po.Item;
import com.limemall.item.mapper.ItemMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.LongAdder;
import java.util.stream.Collectors;

/**
 * 商品详情多级缓存。
 *
 * 读路径：Caffeine（L1）→ Redis（L2）→ 布隆过滤器 → 互斥锁重建 → DB
 * 写路径：Cache Aside（先更新 DB，再删除 L2 缓存，最后广播让所有实例删掉自己的 L1）
 *
 * 三类经典问题的处理：
 *   - 缓存穿透：布隆过滤器拦截不存在的 id；万一误判（布隆说存在但 DB 没有）则缓存空值兜底
 *   - 缓存击穿：热点 key 失效瞬间用 Redis SETNX 互斥锁，只放一个线程回源，其它线程自旋等待
 *   - 缓存雪崩：L2 过期时间加随机抖动；L1 短 TTL 兜住热点读；互斥锁避免同时回源
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ItemCacheService {

    private static final String CACHE_KEY = "item:cache:";
    private static final String LOCK_KEY = "item:lock:";
    /** 空值占位符：缓存不存在的商品，防止同一个不存在的 id 反复穿透到 DB */
    private static final String NULL_MARKER = "__NULL__";

    private final Cache<Long, Object> itemLocalCache;
    private final StringRedisTemplate redis;
    private final ItemMapper itemMapper;
    private final CacheProperties properties;
    private final BloomFilterService bloomFilter;
    private final RabbitTemplate rabbitTemplate;

    /* 统计指标：对外暴露命中率，方便压测与监控 */
    private final LongAdder l1Hit = new LongAdder();
    private final LongAdder l1Miss = new LongAdder();
    private final LongAdder l2Hit = new LongAdder();
    private final LongAdder l2Miss = new LongAdder();
    private final LongAdder dbLoad = new LongAdder();
    private final LongAdder bloomReject = new LongAdder();
    private final LongAdder nullCached = new LongAdder();
    private final LongAdder lockSpin = new LongAdder();
    private final LongAdder lockRebuild = new LongAdder();

    /* ==================== 单条读取 ==================== */

    public ItemDTO getItem(Long id) {
        if (id == null) {
            return null;
        }
        // ① 一级缓存
        Object local = itemLocalCache.getIfPresent(id);
        if (local != null) {
            l1Hit.increment();
            return NULL_MARKER.equals(local) ? null : (ItemDTO) local;
        }
        l1Miss.increment();

        // ② 二级缓存（含空值判断）
        ItemDTO fromL2 = readL2(id);
        if (fromL2 != null) {
            l2Hit.increment();
            itemLocalCache.put(id, fromL2);
            return fromL2;
        }
        if (isNullCached(id)) {
            l2Hit.increment();
            itemLocalCache.put(id, NULL_MARKER);
            return null;
        }
        l2Miss.increment();

        // ③ 布隆过滤器：一定不存在就直接返回，不打数据库
        if (!bloomFilter.mightContain(id)) {
            bloomReject.increment();
            cacheNull(id);
            return null;
        }

        // ④ 互斥锁重建，避免热点 key 失效瞬间大量请求同时回源
        return rebuildWithLock(id);
    }

    /* ==================== 批量读取 ==================== */

    /**
     * 批量读取（购物车、交易服务通过 Feign 调用）。
     * 用 Redis MGET 一次取回多个 key，避免 N 次网络往返。
     */
    public List<ItemDTO> getItems(Collection<Long> ids) {
        List<ItemDTO> result = new ArrayList<>();
        if (CollUtils.isEmpty(ids)) {
            return result;
        }
        List<Long> distinct = ids.stream().filter(java.util.Objects::nonNull).distinct().collect(Collectors.toList());
        Map<Long, ItemDTO> found = new HashMap<>(distinct.size());

        // ① 一级缓存
        List<Long> missInL1 = new ArrayList<>();
        for (Long id : distinct) {
            Object local = itemLocalCache.getIfPresent(id);
            if (local != null) {
                l1Hit.increment();
                if (!NULL_MARKER.equals(local)) {
                    found.put(id, (ItemDTO) local);
                }
            } else {
                l1Miss.increment();
                missInL1.add(id);
            }
        }

        if (!missInL1.isEmpty()) {
            // ② 二级缓存批量读取
            List<String> keys = missInL1.stream().map(id -> CACHE_KEY + id).collect(Collectors.toList());
            List<String> values = redis.opsForValue().multiGet(keys);
            List<Long> needDb = new ArrayList<>();
            for (int i = 0; i < missInL1.size(); i++) {
                Long id = missInL1.get(i);
                String value = values == null ? null : values.get(i);
                if (NULL_MARKER.equals(value)) {
                    l2Hit.increment();
                    itemLocalCache.put(id, NULL_MARKER);
                } else if (value != null) {
                    l2Hit.increment();
                    ItemDTO dto = JSONUtil.toBean(value, ItemDTO.class);
                    itemLocalCache.put(id, dto);
                    found.put(id, dto);
                } else {
                    l2Miss.increment();
                    needDb.add(id);
                }
            }

            // ③ 布隆过滤器 + 回源数据库
            if (!needDb.isEmpty()) {
                List<Long> candidates = new ArrayList<>();
                for (Long id : needDb) {
                    if (bloomFilter.mightContain(id)) {
                        candidates.add(id);
                    } else {
                        bloomReject.increment();
                        cacheNull(id);
                    }
                }
                if (!candidates.isEmpty()) {
                    List<Item> items = itemMapper.selectBatchIds(candidates);
                    dbLoad.add(items.size());
                    Set<Long> hitIds = new HashSet<>();
                    for (Item item : items) {
                        hitIds.add(item.getId());
                        ItemDTO dto = BeanUtils.copyBean(item, ItemDTO.class);
                        itemLocalCache.put(item.getId(), dto);
                        writeL2(item.getId(), JSONUtil.toJsonStr(dto));
                        found.put(item.getId(), dto);
                    }
                    // 布隆误判（说存在但库里没有）→ 缓存空值兜底
                    for (Long id : candidates) {
                        if (!hitIds.contains(id)) {
                            cacheNull(id);
                        }
                    }
                }
            }
        }

        // 按入参顺序返回
        for (Long id : distinct) {
            ItemDTO dto = found.get(id);
            if (dto != null) {
                result.add(dto);
            }
        }
        return result;
    }

    /* ==================== 失效 ==================== */

    /**
     * 删除缓存：先删 L2，再删本地 L1，最后广播让其它实例删掉各自的 L1。
     * 由「更新/上下架/删除商品」的接口在写库成功后调用。
     */
    public void evict(Long id) {
        redis.delete(CACHE_KEY + id);
        itemLocalCache.invalidate(id);
        try {
            // fanout 广播，所有实例都会收到（包括自己，重复删一次无副作用）
            rabbitTemplate.convertAndSend(CacheMqConfig.ITEM_CACHE_EXCHANGE, "", id);
        } catch (Exception e) {
            log.warn("[缓存] 广播失效消息失败，其它实例的本地缓存将在 TTL 后自然过期 itemId={}", id, e);
        }
        log.info("[缓存] 已失效 itemId={}", id);
    }

    /** 供 MQ 监听器调用：只清理本地缓存 */
    public void evictLocal(Long id) {
        if (id != null) {
            itemLocalCache.invalidate(id);
            log.debug("[缓存] 收到广播，清理本地缓存 itemId={}", id);
        }
    }

    /* ==================== 统计 ==================== */

    public Map<String, Object> stats() {
        CacheStats caffeine = itemLocalCache.stats();
        Map<String, Object> map = new LinkedHashMap<>();
        Map<String, Object> l1 = new LinkedHashMap<>();
        l1.put("hit", l1Hit.sum());
        l1.put("miss", l1Miss.sum());
        l1.put("size", itemLocalCache.estimatedSize());
        l1.put("caffeineHitRate", String.format("%.4f", caffeine.hitRate()));
        Map<String, Object> l2 = new LinkedHashMap<>();
        l2.put("hit", l2Hit.sum());
        l2.put("miss", l2Miss.sum());
        long l2Total = l2Hit.sum() + l2Miss.sum();
        l2.put("hitRate", l2Total == 0 ? "0" : String.format("%.4f", (double) l2Hit.sum() / l2Total));
        Map<String, Object> db = new LinkedHashMap<>();
        db.put("loads", dbLoad.sum());
        db.put("bloomRejects", bloomReject.sum());
        db.put("nullCached", nullCached.sum());
        db.put("lockRebuilds", lockRebuild.sum());
        db.put("lockSpins", lockSpin.sum());
        map.put("l1", l1);
        map.put("l2", l2);
        map.put("db", db);
        return map;
    }

    /* ==================== 内部方法 ==================== */

    private ItemDTO rebuildWithLock(Long id) {
        String lockKey = LOCK_KEY + id;
        Boolean locked = redis.opsForValue().setIfAbsent(lockKey, "1",
                Duration.ofSeconds(properties.getLock().getTimeoutSeconds()));
        if (Boolean.TRUE.equals(locked)) {
            try {
                // 双重检查：拿锁期间可能已被其它线程重建
                ItemDTO cached = readL2(id);
                if (cached != null) {
                    itemLocalCache.put(id, cached);
                    return cached;
                }
                if (isNullCached(id)) {
                    itemLocalCache.put(id, NULL_MARKER);
                    return null;
                }
                Item item = itemMapper.selectById(id);
                dbLoad.increment();
                lockRebuild.increment();
                if (item == null) {
                    cacheNull(id);
                    return null;
                }
                ItemDTO dto = BeanUtils.copyBean(item, ItemDTO.class);
                writeL2(id, JSONUtil.toJsonStr(dto));
                itemLocalCache.put(id, dto);
                return dto;
            } finally {
                redis.delete(lockKey);
            }
        }

        // 没抢到锁：短暂自旋等待重建结果，避免把压力转嫁给数据库
        for (int i = 0; i < properties.getLock().getMaxRetries(); i++) {
            sleep(properties.getLock().getWaitMillis());
            ItemDTO cached = readL2(id);
            if (cached != null) {
                lockSpin.increment();
                itemLocalCache.put(id, cached);
                return cached;
            }
            if (isNullCached(id)) {
                lockSpin.increment();
                itemLocalCache.put(id, NULL_MARKER);
                return null;
            }
        }

        // 自旋仍未拿到（极端情况）：退化为直接查库，保证请求不被阻塞
        log.warn("[缓存] 自旋等待超时，退化为直接查库 itemId={}", id);
        Item item = itemMapper.selectById(id);
        dbLoad.increment();
        if (item == null) {
            cacheNull(id);
            return null;
        }
        return BeanUtils.copyBean(item, ItemDTO.class);
    }

    private ItemDTO readL2(Long id) {
        String value = redis.opsForValue().get(CACHE_KEY + id);
        if (value == null || NULL_MARKER.equals(value)) {
            return null;
        }
        return JSONUtil.toBean(value, ItemDTO.class);
    }

    private boolean isNullCached(Long id) {
        return NULL_MARKER.equals(redis.opsForValue().get(CACHE_KEY + id));
    }

    private void writeL2(Long id, String json) {
        // 过期时间加随机抖动，避免同一批 key 同时失效造成雪崩
        long jitter = properties.getRedis().getJitterSeconds();
        long ttl = properties.getRedis().getTtlSeconds()
                + (jitter > 0 ? ThreadLocalRandom.current().nextLong(jitter + 1) : 0);
        redis.opsForValue().set(CACHE_KEY + id, json, Duration.ofSeconds(ttl));
    }

    private void cacheNull(Long id) {
        redis.opsForValue().set(CACHE_KEY + id, NULL_MARKER,
                Duration.ofSeconds(properties.getNullTtlSeconds()));
        itemLocalCache.put(id, NULL_MARKER);
        nullCached.increment();
    }

    private void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
