package com.limemall.seckill.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.toolkit.IdWorker;
import com.limemall.api.client.ItemClient;
import com.limemall.api.dto.ItemDTO;
import com.limemall.common.exception.BizIllegalException;
import com.limemall.common.exception.UnauthorizedException;
import com.limemall.common.utils.BeanUtils;
import com.limemall.common.utils.CollUtils;
import com.limemall.common.utils.UserContext;
import com.limemall.seckill.config.SeckillProperties;
import com.limemall.seckill.constant.SeckillConstants;
import com.limemall.seckill.domain.dto.SeckillMessage;
import com.limemall.seckill.domain.po.SeckillActivity;
import com.limemall.seckill.domain.po.SeckillOrder;
import com.limemall.seckill.domain.vo.SeckillActivityVO;
import com.limemall.seckill.domain.vo.SeckillResultVO;
import com.limemall.seckill.mapper.SeckillActivityMapper;
import com.limemall.seckill.mapper.SeckillOrderMapper;
import com.limemall.seckill.service.ISeckillService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 秒杀核心实现。
 *
 * 抗并发的三道闸门：
 *   1. 令牌桶限流（Redis + Lua，多实例共享额度）——把超过系统处理能力的请求挡在业务逻辑之外
 *   2. Redis Lua 原子预扣库存 + 一人一单 ——不碰数据库，单机可支撑数万 QPS
 *   3. RabbitMQ 异步落库 ——把瞬时写压力削峰，消费端按自己的节奏扣真实库存
 *
 * 一致性与补偿：
 *   - 预扣成功但投递失败：立即回补 Redis（本地事务性回滚）
 *   - 投递成功但消费失败：MQ 自动重试 3 次，仍失败则交给定时对账任务补偿
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SeckillServiceImpl implements ISeckillService {

    private final SeckillActivityMapper activityMapper;
    private final SeckillOrderMapper orderMapper;
    private final StringRedisTemplate redis;
    private final DefaultRedisScript<Long> seckillStockScript;
    private final DefaultRedisScript<Long> rateLimitScript;
    private final SeckillProperties properties;
    private final RabbitTemplate rabbitTemplate;
    private final ItemClient itemClient;

    @Override
    public SeckillResultVO seckill(Long activityId) {
        Long userId = currentUserId();

        // ① 令牌桶限流
        if (!tryAcquire(activityId)) {
            log.warn("[秒杀] 触发限流 activityId={}, userId={}", activityId, userId);
            return SeckillResultVO.fail("当前抢购人数过多，请稍后再试", remainStock(activityId));
        }

        // ② 活动校验（优先读缓存，未命中回源 DB 并预热）
        SeckillActivity activity = loadActivity(activityId);
        if (activity == null) {
            return SeckillResultVO.fail("活动不存在", 0L);
        }
        if (!activity.isOngoing()) {
            return SeckillResultVO.fail("活动尚未开始或已结束", remainStock(activityId));
        }

        // ③ Lua 原子预扣：校验库存 + 校验一人一单 + 扣减 + 记录买家
        Long raw = redis.execute(seckillStockScript,
                List.of(SeckillConstants.STOCK_KEY + activityId, SeckillConstants.BUYERS_KEY + activityId),
                userId.toString());
        long result = raw == null ? SeckillConstants.DEDUCT_NOT_READY : raw;

        if (result == SeckillConstants.DEDUCT_SOLD_OUT) {
            return SeckillResultVO.fail("已售罄", 0L);
        }
        if (result == SeckillConstants.DEDUCT_REPEAT) {
            return SeckillResultVO.fail("你已抢到过该商品，每人限购 1 件", remainStock(activityId));
        }
        if (result == SeckillConstants.DEDUCT_NOT_READY) {
            // 缓存未预热：本次请求按失败处理，主动预热后由用户重试
            cacheActivity(activity, true);
            return SeckillResultVO.fail("活动正在准备中，请稍后重试", remainStock(activityId));
        }

        // ④ 预生成订单号 + 异步投递
        long orderId = IdWorker.getId();
        SeckillMessage message = new SeckillMessage(orderId, activityId, userId,
                activity.getItemId(), activity.getSeckillPrice(), 1);
        try {
            rabbitTemplate.convertAndSend(SeckillConstants.ORDER_EXCHANGE,
                    SeckillConstants.ORDER_ROUTING_KEY, message);
        } catch (Exception e) {
            // 投递失败必须回补，否则库存会被白白扣掉
            rollbackRedis(activityId, userId);
            log.error("[秒杀] 消息投递失败，已回补预扣 activityId={}, userId={}", activityId, userId, e);
            return SeckillResultVO.fail("系统繁忙，请重试", remainStock(activityId));
        }

        log.info("[秒杀] 预扣成功 activityId={}, userId={}, orderId={}, 剩余={}",
                activityId, userId, orderId, remainStock(activityId));
        return SeckillResultVO.ok(orderId, remainStock(activityId));
    }

    @Override
    public SeckillResultVO queryResult(Long orderId) {
        SeckillOrder order = orderMapper.selectById(orderId);
        if (order == null) {
            // 已预扣但尚未落库，属于正常的中间态
            return new SeckillResultVO(true, orderId, "排队中，请稍后查询", null);
        }
        String message;
        switch (order.getStatus()) {
            case SeckillConstants.STATUS_PROCESSING:
                message = "排队中，请稍后查询";
                break;
            case SeckillConstants.STATUS_WAIT_PAY:
                message = "抢购成功，请尽快支付";
                break;
            case SeckillConstants.STATUS_PAID:
                message = "已支付";
                break;
            case SeckillConstants.STATUS_CANCELED:
                message = "订单已取消";
                break;
            default:
                message = "抢购失败，库存已回补";
                break;
        }
        boolean success = order.getStatus() != SeckillConstants.STATUS_FAILED;
        return new SeckillResultVO(success, orderId, message, null);
    }

    @Override
    public SeckillActivityVO queryActivity(Long activityId) {
        SeckillActivity activity = activityMapper.selectById(activityId);
        if (activity == null) {
            throw new BizIllegalException("活动不存在");
        }
        SeckillActivityVO vo = BeanUtils.copyBean(activity, SeckillActivityVO.class);
        List<ItemDTO> items = itemClient.queryItemByIds(Collections.singletonList(activity.getItemId()));
        if (CollUtils.isNotEmpty(items)) {
            ItemDTO item = items.get(0);
            vo.setItemName(item.getName());
            vo.setItemImage(item.getImage());
            vo.setOriginPrice(item.getPrice());
        }
        vo.setRemainStock(remainStock(activityId));
        vo.setOngoing(activity.isOngoing());
        return vo;
    }

    @Override
    public void warmUp(Long activityId) {
        SeckillActivity activity = activityMapper.selectById(activityId);
        if (activity == null) {
            throw new BizIllegalException("活动不存在");
        }
        cacheActivity(activity, true);
        redis.delete(SeckillConstants.BUYERS_KEY + activityId);
        redis.opsForValue().set(SeckillConstants.STOCK_KEY + activityId,
                String.valueOf(activity.getAvailableStock()), Duration.ofHours(2));
        log.info("[秒杀] 活动 {} 预热完成，可售库存 {}", activityId, activity.getAvailableStock());
    }

    @Override
    public void markPaid(Long orderId) {
        if (orderId == null) {
            return;
        }
        // 只有「待支付」的秒杀订单才会被推进（订单号同时也是交易订单号，非秒杀订单查不到就忽略）
        SeckillOrder order = orderMapper.selectById(orderId);
        if (order == null) {
            log.debug("[秒杀支付同步] 非秒杀订单，忽略 orderId={}", orderId);
            return;
        }
        if (order.getStatus() != null && order.getStatus() == SeckillConstants.STATUS_PAID) {
            log.info("[秒杀支付同步] 订单已是已支付状态，忽略重复消息 orderId={}", orderId);
            return;
        }
        orderMapper.updateById(new SeckillOrder()
                .setId(orderId)
                .setStatus(SeckillConstants.STATUS_PAID));
        log.info("[秒杀支付同步] 秒杀订单已更新为已支付 orderId={}", orderId);
    }

    /**
     * 对照实现：不经过 Redis，直接数据库悲观锁 + 同步落库。
     * 用于压测时对比「直接压库」与「Redis 预扣 + MQ 异步」的吞吐差异。
     */
    @Override
    @Transactional
    public SeckillResultVO seckillByDatabase(Long activityId) {
        Long userId = currentUserId();

        SeckillActivity activity = activityMapper.selectOne(new QueryWrapper<SeckillActivity>()
                .eq("id", activityId)
                .last("FOR UPDATE"));
        if (activity == null || !activity.isOngoing()) {
            return SeckillResultVO.fail("活动不存在或已结束", 0L);
        }
        if (activity.getAvailableStock() <= 0) {
            return SeckillResultVO.fail("已售罄", 0L);
        }
        Integer bought = orderMapper.selectCount(new QueryWrapper<SeckillOrder>()
                .eq("activity_id", activityId)
                .eq("user_id", userId));
        if (bought != null && bought > 0) {
            return SeckillResultVO.fail("你已抢到过该商品", (long) activity.getAvailableStock());
        }
        if (activityMapper.deductStock(activityId, 1) == 0) {
            return SeckillResultVO.fail("已售罄", 0L);
        }
        SeckillOrder order = new SeckillOrder()
                .setId(IdWorker.getId())
                .setActivityId(activityId)
                .setUserId(userId)
                .setItemId(activity.getItemId())
                .setNum(1)
                .setPrice(activity.getSeckillPrice())
                .setStatus(SeckillConstants.STATUS_WAIT_PAY);
        orderMapper.insert(order);
        // 同步扣商品库存（数据库链路没有削峰，这一步会直接压到商品服务）
        itemClient.deductStock(Collections.singletonList(
                new com.limemall.api.dto.OrderDetailDTO().setItemId(activity.getItemId()).setNum(1)));
        return SeckillResultVO.ok(order.getId(), (long) activity.getAvailableStock() - 1);
    }

    /* ==================== 内部方法 ==================== */

    private Long currentUserId() {
        Long userId = UserContext.getUser();
        if (userId == null) {
            throw new UnauthorizedException("请先登录");
        }
        return userId;
    }

    /** 令牌桶：容量与速率来自配置，多实例共享同一个桶 */
    private boolean tryAcquire(Long activityId) {
        Long allowed = redis.execute(rateLimitScript,
                Collections.singletonList(SeckillConstants.BUCKET_KEY + activityId),
                String.valueOf(properties.getRateLimit().getCapacity()),
                String.valueOf(properties.getRateLimit().getRate()),
                String.valueOf(System.currentTimeMillis()),
                "1");
        return allowed != null && allowed == 1L;
    }

    /** 活动信息：优先读 Redis Hash，未命中回源 DB 并写缓存 */
    private SeckillActivity loadActivity(Long activityId) {
        String key = SeckillConstants.ACTIVITY_KEY + activityId;
        Map<Object, Object> cached = redis.opsForHash().entries(key);
        if (cached != null && !cached.isEmpty()) {
            SeckillActivity activity = new SeckillActivity();
            activity.setId(activityId);
            activity.setItemId(Long.valueOf(String.valueOf(cached.get("itemId"))));
            activity.setSeckillPrice(Integer.valueOf(String.valueOf(cached.get("price"))));
            activity.setTotalStock(Integer.valueOf(String.valueOf(cached.get("totalStock"))));
            activity.setStatus(Integer.valueOf(String.valueOf(cached.get("status"))));
            activity.setStartTime(toLocalDateTime(cached.get("start")));
            activity.setEndTime(toLocalDateTime(cached.get("end")));
            return activity;
        }
        SeckillActivity activity = activityMapper.selectById(activityId);
        if (activity != null) {
            cacheActivity(activity, false);
        }
        return activity;
    }

    /**
     * 写入活动缓存。
     *
     * @param force true=覆盖库存（预热场景）；false=仅在库存 key 不存在时写入，
     *              避免把正在被预扣的实时库存覆盖回旧值
     */
    private void cacheActivity(SeckillActivity activity, boolean force) {
        String key = SeckillConstants.ACTIVITY_KEY + activity.getId();
        Map<String, String> hash = new HashMap<>(8);
        hash.put("itemId", String.valueOf(activity.getItemId()));
        hash.put("price", String.valueOf(activity.getSeckillPrice()));
        hash.put("totalStock", String.valueOf(activity.getTotalStock()));
        hash.put("status", String.valueOf(activity.getStatus()));
        hash.put("start", String.valueOf(toEpochMilli(activity.getStartTime())));
        hash.put("end", String.valueOf(toEpochMilli(activity.getEndTime())));
        redis.opsForHash().putAll(key, hash);
        redis.expire(key, Duration.ofMinutes(30));

        String stockKey = SeckillConstants.STOCK_KEY + activity.getId();
        String stockValue = String.valueOf(activity.getAvailableStock());
        if (force) {
            redis.opsForValue().set(stockKey, stockValue, Duration.ofHours(2));
        } else {
            redis.opsForValue().setIfAbsent(stockKey, stockValue, Duration.ofHours(2));
        }
    }

    private Long remainStock(Long activityId) {
        String value = redis.opsForValue().get(SeckillConstants.STOCK_KEY + activityId);
        return value == null ? 0L : Long.parseLong(value);
    }

    /** 回补 Redis 预扣（投递失败时使用） */
    private void rollbackRedis(Long activityId, Long userId) {
        try {
            redis.opsForValue().increment(SeckillConstants.STOCK_KEY + activityId);
            redis.opsForSet().remove(SeckillConstants.BUYERS_KEY + activityId, userId.toString());
        } catch (Exception e) {
            log.error("[秒杀] 回补 Redis 失败 activityId={}, userId={}", activityId, userId, e);
        }
    }

    private long toEpochMilli(LocalDateTime time) {
        return time == null ? 0L : time.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();
    }

    private LocalDateTime toLocalDateTime(Object epochMilli) {
        long millis = Long.parseLong(String.valueOf(epochMilli));
        return millis <= 0 ? null : LocalDateTime.ofInstant(Instant.ofEpochMilli(millis), ZoneId.systemDefault());
    }
}
