package com.limemall.seckill.constant;

/**
 * 秒杀相关的常量：Redis key 前缀、MQ 名称、Lua 返回值、订单状态。
 */
public interface SeckillConstants {

    /* ---------------- Redis key ---------------- */
    /** 剩余可售库存：seckill:stock:{activityId} */
    String STOCK_KEY = "seckill:stock:";
    /** 已下单用户集合（一人一单）：seckill:buyers:{activityId} */
    String BUYERS_KEY = "seckill:buyers:";
    /** 令牌桶：seckill:bucket:{activityId} */
    String BUCKET_KEY = "seckill:bucket:";
    /** 活动缓存：seckill:activity:{activityId} */
    String ACTIVITY_KEY = "seckill:activity:";

    /* ---------------- MQ ---------------- */
    String ORDER_EXCHANGE = "seckill.direct";
    String ORDER_QUEUE = "seckill.order.queue";
    String ORDER_ROUTING_KEY = "seckill.order";

    /* ---------------- Lua 预扣返回值 ---------------- */
    long DEDUCT_SUCCESS = 1L;
    long DEDUCT_SOLD_OUT = 0L;
    long DEDUCT_REPEAT = -1L;
    long DEDUCT_NOT_READY = -2L;

    /* ---------------- 秒杀订单状态 ---------------- */
    /** 处理中：Redis 已预扣，等待异步落库 */
    int STATUS_PROCESSING = 0;
    /** 中间状态：活动与商品库存已扣减，等待生成交易订单（用于让补偿可重入、不重复扣库存） */
    int STATUS_STOCK_DEDUCTED = 5;
    /** 待支付 */
    int STATUS_WAIT_PAY = 1;
    /** 已支付 */
    int STATUS_PAID = 2;
    /** 已取消 */
    int STATUS_CANCELED = 3;
    /** 失败：需要回补库存并清理购买记录 */
    int STATUS_FAILED = 9;
}
