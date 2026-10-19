package com.limemall.item.mq;

import com.limemall.item.service.ItemCacheService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 监听缓存失效广播：每个实例都有自己的匿名队列，因此消息会被所有实例消费到。
 * 收到后只清理本进程的 Caffeine 缓存（Redis 二级缓存已由更新方删除）。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class CacheInvalidateListener {

    private final ItemCacheService itemCacheService;

    @RabbitListener(queues = "#{itemCacheInvalidateQueue.name}")
    public void onCacheInvalidate(Long itemId) {
        itemCacheService.evictLocal(itemId);
    }
}
