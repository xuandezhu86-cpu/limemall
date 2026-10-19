package com.limemall.seckill.config;

import com.limemall.seckill.constant.SeckillConstants;
import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 秒杀下单的 MQ 拓扑：
 *   seckill.direct（直连交换机） --seckill.order--> seckill.order.queue
 * 消费失败的商品消息由对账任务兜底补偿。
 */
@Configuration
public class SeckillMqConfig {

    @Bean
    public DirectExchange seckillOrderExchange() {
        return new DirectExchange(SeckillConstants.ORDER_EXCHANGE, true, false);
    }

    @Bean
    public Queue seckillOrderQueue() {
        return QueueBuilder.durable(SeckillConstants.ORDER_QUEUE).build();
    }

    @Bean
    public Binding seckillOrderBinding(Queue seckillOrderQueue, DirectExchange seckillOrderExchange) {
        return BindingBuilder.bind(seckillOrderQueue)
                .to(seckillOrderExchange)
                .with(SeckillConstants.ORDER_ROUTING_KEY);
    }
}
