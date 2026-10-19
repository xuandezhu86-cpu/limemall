package com.limemall.seckill.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.core.script.DefaultRedisScript;

/**
 * 把 Lua 脚本注册成 Bean，由 Spring 负责读取与缓存（RedisTemplate 会自动用 EVALSHA 执行）。
 */
@Configuration
public class SeckillRedisConfig {

    /** 库存原子预扣脚本 */
    @Bean
    public DefaultRedisScript<Long> seckillStockScript() {
        DefaultRedisScript<Long> script = new DefaultRedisScript<>();
        script.setLocation(new ClassPathResource("lua/seckill_stock.lua"));
        script.setResultType(Long.class);
        return script;
    }

    /** 令牌桶限流脚本 */
    @Bean
    public DefaultRedisScript<Long> rateLimitScript() {
        DefaultRedisScript<Long> script = new DefaultRedisScript<>();
        script.setLocation(new ClassPathResource("lua/rate_limit.lua"));
        script.setResultType(Long.class);
        return script;
    }
}
