package com.limemall.seckill.mq;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.limemall.api.client.ItemClient;
import com.limemall.api.client.TradeClient;
import com.limemall.api.dto.OrderDetailDTO;
import com.limemall.api.dto.SeckillOrderDTO;
import com.limemall.common.exception.BizIllegalException;
import com.limemall.seckill.constant.SeckillConstants;
import com.limemall.seckill.domain.dto.SeckillMessage;
import com.limemall.seckill.domain.po.SeckillOrder;
import com.limemall.seckill.mapper.SeckillActivityMapper;
import com.limemall.seckill.mapper.SeckillOrderMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Component;

import java.util.Collections;

/**
 * 秒杀订单消费者：把 Redis 预扣转换成真实订单。
 *
 * 幂等设计（消息可能重复投递）：
 *   1. 先按 (activityId, userId) 查一次，已存在直接返回
 *   2. 插入时依赖唯一索引 uk_activity_user 兜底，捕获 DuplicateKeyException 视为重复
 *   3. complete() 用中间状态 STATUS_STOCK_DEDUCTED 记录「库存已扣」，重试时跳过扣减步骤，
 *      避免补偿流程把库存扣两次
 *   （消费失败会触发 Spring AMQP 重试，最多 3 次，仍失败则由对账任务补偿）
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SeckillOrderConsumer {

    private final SeckillOrderMapper orderMapper;
    private final SeckillActivityMapper activityMapper;
    private final ItemClient itemClient;
    private final TradeClient tradeClient;

    @RabbitListener(queues = SeckillConstants.ORDER_QUEUE)
    public void handleSeckillOrder(SeckillMessage message) {
        log.info("[秒杀消费] 收到下单消息 activityId={}, userId={}, orderId={}",
                message.getActivityId(), message.getUserId(), message.getOrderId());

        SeckillOrder exist = orderMapper.selectOne(new LambdaQueryWrapper<SeckillOrder>()
                .eq(SeckillOrder::getActivityId, message.getActivityId())
                .eq(SeckillOrder::getUserId, message.getUserId()));
        if (exist != null) {
            log.info("[秒杀消费] 用户已存在秒杀订单，忽略重复消息 orderId={}", exist.getId());
            return;
        }

        SeckillOrder order = new SeckillOrder()
                .setId(message.getOrderId())
                .setActivityId(message.getActivityId())
                .setUserId(message.getUserId())
                .setItemId(message.getItemId())
                .setNum(message.getNum())
                .setPrice(message.getPrice())
                .setStatus(SeckillConstants.STATUS_PROCESSING);
        try {
            orderMapper.insert(order);
        } catch (DuplicateKeyException e) {
            log.info("[秒杀消费] 唯一索引命中，判定为重复下单 userId={}", message.getUserId());
            return;
        }

        complete(order);
    }

    /**
     * 完成下单：扣活动库存 -> 扣商品真实库存 -> 生成交易订单 -> 状态改为待支付。
     * 由 MQ 消费与对账任务共同调用，因此必须可重复执行：
     * 库存扣减只在「处理中」状态下执行一次，之后用 STATUS_STOCK_DEDUCTED 记录进度。
     */
    public void complete(SeckillOrder order) {
        Integer status = order.getStatus();
        boolean stockDeducted = status != null && status == SeckillConstants.STATUS_STOCK_DEDUCTED;
        if (status != null && !stockDeducted && status != SeckillConstants.STATUS_PROCESSING) {
            log.info("[秒杀消费] 订单已处理，跳过 orderId={}, status={}", order.getId(), status);
            return;
        }

        if (!stockDeducted) {
            // 1) 扣活动可售库存（条件更新，数据库层兜底防超卖）
            int updated = activityMapper.deductStock(order.getActivityId(), order.getNum());
            if (updated == 0) {
                throw new BizIllegalException("活动库存不足，无法完成秒杀订单：" + order.getId());
            }

            // 2) 扣商品真实库存（Feign 调用商品服务，库存不足会抛异常触发重试）
            itemClient.deductStock(Collections.singletonList(
                    new OrderDetailDTO().setItemId(order.getItemId()).setNum(order.getNum())));

            // 3) 记录中间状态：库存已扣，重试时不再重复扣
            orderMapper.updateById(new SeckillOrder()
                    .setId(order.getId())
                    .setStatus(SeckillConstants.STATUS_STOCK_DEDUCTED));
            order.setStatus(SeckillConstants.STATUS_STOCK_DEDUCTED);
        } else {
            log.info("[秒杀消费] 库存此前已扣减，直接补建交易订单 orderId={}", order.getId());
        }

        // 4) 生成交易订单：用户凭这个订单号才能走支付流程（幂等，重复调用返回同一个订单）
        tradeClient.createSeckillOrder(new SeckillOrderDTO()
                .setOrderId(order.getId())
                .setUserId(order.getUserId())
                .setItemId(order.getItemId())
                .setNum(order.getNum())
                .setPrice(order.getPrice()));

        // 5) 状态推进为待支付
        orderMapper.updateById(new SeckillOrder()
                .setId(order.getId())
                .setStatus(SeckillConstants.STATUS_WAIT_PAY));
        log.info("[秒杀消费] 落库完成 orderId={}, activityId={}, userId={}",
                order.getId(), order.getActivityId(), order.getUserId());
    }
}
