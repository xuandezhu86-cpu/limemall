package com.limemall.item.config;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * 一级缓存（进程内）：Caffeine。
 * 选它是因为读性能最好（无网络开销），但只在单实例内有效，所以必须配合广播失效。
 */
@Configuration
public class LocalCacheConfig {

    @Bean
    public Cache<Long, Object> itemLocalCache(CacheProperties properties) {
        return Caffeine.newBuilder()
                .maximumSize(properties.getLocal().getMaximumSize())
                .expireAfterWrite(Duration.ofSeconds(properties.getLocal().getExpireAfterWriteSeconds()))
                .recordStats()
                .build();
    }
}
