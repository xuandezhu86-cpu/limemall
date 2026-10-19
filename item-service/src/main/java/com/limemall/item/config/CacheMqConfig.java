package com.limemall.item.config;

import org.springframework.amqp.core.AnonymousQueue;
import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.FanoutExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 缓存失效广播的 MQ 拓扑。
 *
 * 多级缓存的经典难题：一级缓存（Caffeine）在各自进程里，某个实例更新了数据，
 * 其它实例的本地缓存还是旧值。这里的做法是：
 *   - 声明一个 fanout 交换机
 *   - 每个实例启动时绑定一个匿名队列（exclusive + auto-delete），因此每条消息都会被所有实例收到
 *   - 收到消息的实例只清理自己的本地缓存（Redis 二级缓存由更新方直接删除）
 */
@Configuration
public class CacheMqConfig {

    public static final String ITEM_CACHE_EXCHANGE = "item.cache.invalidate";

    @Bean
    public FanoutExchange itemCacheExchange() {
        return new FanoutExchange(ITEM_CACHE_EXCHANGE, true, false);
    }

    @Bean
    public Queue itemCacheInvalidateQueue() {
        // 匿名队列：名字由框架生成，每个实例一个，断连自动删除
        return new AnonymousQueue();
    }

    @Bean
    public Binding itemCacheInvalidateBinding(Queue itemCacheInvalidateQueue, FanoutExchange itemCacheExchange) {
        return BindingBuilder.bind(itemCacheInvalidateQueue).to(itemCacheExchange);
    }
}
