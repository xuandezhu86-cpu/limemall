package com.limemall.seckill.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 秒杀可调参数（application.yaml 中的 seckill.*）。
 */
@Data
@Component
@ConfigurationProperties(prefix = "seckill")
public class SeckillProperties {

    private RateLimit rateLimit = new RateLimit();
    private Reconcile reconcile = new Reconcile();

    @Data
    public static class RateLimit {
        /** 令牌桶容量，允许的瞬时突发量 */
        private int capacity = 3000;
        /** 每秒补充的令牌数，即稳态 QPS 上限 */
        private int rate = 1500;
    }

    @Data
    public static class Reconcile {
        /** 对账任务执行周期 */
        private String cron = "0/30 * * * * ?";
        /** 处理中订单超过多少秒仍未完成，触发补偿 */
        private int timeoutSeconds = 30;
        /** Redis 与 DB 库存差异容忍度，超过则打告警日志 */
        private int stockTolerance = 0;
    }
}
