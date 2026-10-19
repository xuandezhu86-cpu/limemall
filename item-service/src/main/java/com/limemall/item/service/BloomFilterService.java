package com.limemall.item.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.limemall.item.config.CacheProperties;
import com.limemall.item.domain.po.Item;
import com.limemall.item.mapper.ItemMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.List;

/**
 * 基于 Redis 位图实现的布隆过滤器，用于拦截「一定不存在」的商品 id（防缓存穿透）。
 *
 * 原理：用 k 个哈希函数把元素映射到位图的 k 个 bit 上，查询时只要有一个 bit 为 0 就说明元素一定不存在。
 * 因此它只会「误判存在」（可用空间换取误判率），不会漏判——正好适合做缓存前置拦截。
 *
 * 这里用 MD5 的 16 字节切成 4 个 int 作为 4 个哈希值（k=4），位图 16M bit ≈ 2MB。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class BloomFilterService {

    private static final String BLOOM_KEY = "item:bloom";

    private final StringRedisTemplate redis;
    private final CacheProperties properties;
    private final ItemMapper itemMapper;

    /** 应用启动时把已有商品 id 灌进布隆过滤器 */
    @PostConstruct
    public void init() {
        try {
            rebuild();
        } catch (Exception e) {
            log.error("[布隆过滤器] 初始化失败，将退化为直接查库", e);
        }
    }

    /** 全量重建（商品批量导入后可手动调用） */
    public void rebuild() {
        List<Object> ids = itemMapper.selectObjs(new QueryWrapper<Item>().select("id"));
        redis.delete(BLOOM_KEY);
        for (Object id : ids) {
            add(Long.valueOf(String.valueOf(id)));
        }
        log.info("[布隆过滤器] 初始化完成：元素 {} 个，位图 {} bit，哈希函数 {} 个",
                ids.size(), properties.getBloom().getBitSize(), properties.getBloom().getHashCount());
    }

    /** 新增商品时写入 */
    public void add(Long id) {
        if (id == null) {
            return;
        }
        for (long index : indexes(id)) {
            redis.opsForValue().setBit(BLOOM_KEY, index, true);
        }
    }

    /** false = 一定不存在；true = 可能存在（需回源确认） */
    public boolean mightContain(Long id) {
        if (id == null) {
            return false;
        }
        for (long index : indexes(id)) {
            Boolean bit = redis.opsForValue().getBit(BLOOM_KEY, index);
            if (bit == null || !bit) {
                return false;
            }
        }
        return true;
    }

    /** 计算 k 个位图下标 */
    private long[] indexes(Long id) {
        long bitSize = properties.getBloom().getBitSize();
        int hashCount = Math.min(properties.getBloom().getHashCount(), 4);
        byte[] digest = md5(String.valueOf(id));
        long[] result = new long[hashCount];
        for (int i = 0; i < hashCount; i++) {
            int offset = i * 4;
            long hash = ((long) (digest[offset] & 0xFF) << 24)
                    | ((long) (digest[offset + 1] & 0xFF) << 16)
                    | ((long) (digest[offset + 2] & 0xFF) << 8)
                    | (digest[offset + 3] & 0xFF);
            result[i] = Math.abs(hash % bitSize);
        }
        return result;
    }

    private byte[] md5(String value) {
        try {
            return MessageDigest.getInstance("MD5").digest(value.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("MD5 not available", e);
        }
    }
}
