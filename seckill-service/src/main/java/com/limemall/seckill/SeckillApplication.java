package com.limemall.seckill;

import com.limemall.api.config.DefaultFeignConfig;
import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.openfeign.EnableFeignClients;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 秒杀服务启动类。
 *
 * 与商品/交易服务不同，秒杀场景追求「抗瞬时高并发」而不是「强一致」：
 *   - 库存预扣放在 Redis（Lua 原子执行），不直接压数据库
 *   - 下单请求经 RabbitMQ 异步落库，把流量峰值削平
 *   - 因此这里不引入 Seata 全局事务，改用「预扣 + 异步落库 + 定时对账补偿」的最终一致方案
 */
@EnableScheduling
@EnableFeignClients(basePackages = "com.limemall.api.client", defaultConfiguration = DefaultFeignConfig.class)
@MapperScan("com.limemall.seckill.mapper")
@SpringBootApplication
public class SeckillApplication {

    public static void main(String[] args) {
        SpringApplication.run(SeckillApplication.class, args);
    }
}
