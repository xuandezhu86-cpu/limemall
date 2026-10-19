package com.limemall.seckill.task;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.limemall.common.utils.CollUtils;
import com.limemall.seckill.config.SeckillProperties;
import com.limemall.seckill.constant.SeckillConstants;
import com.limemall.seckill.domain.po.SeckillActivity;
import com.limemall.seckill.domain.po.SeckillOrder;
import com.limemall.seckill.mapper.SeckillActivityMapper;
import com.limemall.seckill.mapper.SeckillOrderMapper;
import com.limemall.seckill.mq.SeckillOrderConsumer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 秒杀对账与补偿任务。
 *
 * 这是「最终一致」方案的最后一环：MQ 只保证尽力投递 + 有限重试，
 * 真正保证数据不会丢的是这里的定时兜底。
 *
 *   1. 补偿：超过阈值仍停留在「处理中」的订单重新驱动；
 *      再次失败则标记失败，并把 Redis 预扣的库存与购买记录回补
 *   2. 校准：对比 Redis 预扣剩余与数据库可售库存，差异超阈值打告警日志
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SeckillReconcileTask {

    private static final int BATCH_LIMIT = 100;

    private final SeckillOrderMapper orderMapper;
    private final SeckillActivityMapper activityMapper;
    private final SeckillOrderConsumer consumer;
    private final StringRedisTemplate redis;
    private final SeckillProperties properties;

    @Scheduled(cron = "${seckill.reconcile.cron:0/30 * * * * ?}")
    public void reconcile() {
        try {
            compensateStuckOrders();
            calibrateStock();
        } catch (Exception e) {
            log.error("[秒杀对账] 任务执行异常", e);
        }
    }

    /** 补偿长时间停留在「处理中」或「库存已扣但未生成交易订单」的订单 */
    private void compensateStuckOrders() {
        LocalDateTime deadline = LocalDateTime.now()
                .minusSeconds(properties.getReconcile().getTimeoutSeconds());
        List<SeckillOrder> stuck = orderMapper.selectList(new LambdaQueryWrapper<SeckillOrder>()
                .in(SeckillOrder::getStatus,
                        SeckillConstants.STATUS_PROCESSING,
                        SeckillConstants.STATUS_STOCK_DEDUCTED)
                .lt(SeckillOrder::getCreateTime, deadline)
                .last("LIMIT " + BATCH_LIMIT));
        if (CollUtils.isEmpty(stuck)) {
            return;
        }
        log.warn("[秒杀对账] 发现 {} 笔超时未完成的秒杀订单，开始补偿", stuck.size());
        for (SeckillOrder order : stuck) {
            try {
                consumer.complete(order);
                log.info("[秒杀对账] 补偿成功 orderId={}", order.getId());
            } catch (Exception e) {
                log.error("[秒杀对账] 补偿失败，回补活动库存与购买记录 orderId={}", order.getId(), e);
                // 已知限制：这里只回补了活动库存与 Redis 预扣，已扣的商品库存没有反向接口，
                // 需要人工介入或补一个 itemClient.restoreStock 才能完全对齐（真实项目可加）。
                orderMapper.updateById(new SeckillOrder()
                        .setId(order.getId())
                        .setStatus(SeckillConstants.STATUS_FAILED));
                activityMapper.restoreStock(order.getActivityId(), order.getNum());
                redis.opsForValue().increment(SeckillConstants.STOCK_KEY + order.getActivityId());
                redis.opsForSet().remove(SeckillConstants.BUYERS_KEY + order.getActivityId(),
                        order.getUserId().toString());
            }
        }
    }

    /** 对比 Redis 预扣库存与数据库可售库存 */
    private void calibrateStock() {
        List<SeckillActivity> activities = activityMapper.selectList(new LambdaQueryWrapper<SeckillActivity>()
                .eq(SeckillActivity::getStatus, 1));
        if (CollUtils.isEmpty(activities)) {
            return;
        }
        for (SeckillActivity activity : activities) {
            String cached = redis.opsForValue().get(SeckillConstants.STOCK_KEY + activity.getId());
            if (cached == null) {
                continue;
            }
            long redisStock = Long.parseLong(cached);
            long dbStock = activity.getAvailableStock();
            long diff = redisStock - dbStock;
            if (Math.abs(diff) > properties.getReconcile().getStockTolerance()) {
                // 存在少量在途消息时 diff 属正常，持续增大或长期不为 0 才说明有消息丢失
                log.warn("[秒杀对账] 库存存在差异 activityId={} redis={} db={} diff={}",
                        activity.getId(), redisStock, dbStock, diff);
            }
        }
    }
}
