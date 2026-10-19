package com.limemall.seckill.mq;

import com.limemall.seckill.service.ISeckillService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.Exchange;
import org.springframework.amqp.rabbit.annotation.Queue;
import org.springframework.amqp.rabbit.annotation.QueueBinding;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 支付成功消息监听：把秒杀订单状态同步为「已支付」。
 *
 * <p>pay-service 支付成功后往 pay.direct 交换机发消息（routing key = pay.success，
 * 内容是交易订单号）。交易服务已经在消费这条消息改订单状态，这里再绑一个自己的队列，
 * 同一个 routing key 会同时投递到两个队列，互不影响。</p>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SeckillPayStatusListener {

    private final ISeckillService seckillService;

    @RabbitListener(bindings = @QueueBinding(
            value = @Queue(name = "seckill.pay.success.queue", durable = "true"),
            exchange = @Exchange(name = "pay.direct"),
            key = "pay.success"
    ))
    public void listenPaySuccess(Long orderId) {
        log.info("[秒杀支付同步] 收到支付成功消息 orderId={}", orderId);
        seckillService.markPaid(orderId);
    }
}
