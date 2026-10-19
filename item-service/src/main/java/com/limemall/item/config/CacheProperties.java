package com.limemall.item.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 多级缓存可调参数（application.yaml 中的 lm.cache.*）。
 */
@Data
@Component
@ConfigurationProperties(prefix = "lm.cache")
public class CacheProperties {

    private Local local = new Local();
    private Redis redis = new Redis();
    private Lock lock = new Lock();
    private Bloom bloom = new Bloom();

    /** 空值缓存时间（秒）：缓存不存在的 id，防止穿透 */
    private long nullTtlSeconds = 60;

    @Data
    public static class Local {
        /** 本地缓存最大条目数 */
        private long maximumSize = 1000;
        /** 写入后过期时间（秒） */
        private long expireAfterWriteSeconds = 30;
    }

    @Data
    public static class Redis {
        /** 基础过期时间（秒） */
        private long ttlSeconds = 600;
        /** 过期时间抖动上限（秒），避免缓存雪崩 */
        private long jitterSeconds = 60;
    }

    @Data
    public static class Lock {
        /** 互斥锁超时（秒） */
        private long timeoutSeconds = 3;
        /** 未抢到锁时的自旋间隔（毫秒） */
        private long waitMillis = 50;
        /** 自旋重试次数 */
        private int maxRetries = 5;
    }

    @Data
    public static class Bloom {
        /** 位图大小（bit） */
        private long bitSize = 1L << 24;
        /** 哈希函数个数 */
        private int hashCount = 4;
    }
}
