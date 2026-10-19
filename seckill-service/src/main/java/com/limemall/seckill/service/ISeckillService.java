package com.limemall.seckill.service;

import com.limemall.seckill.domain.vo.SeckillActivityVO;
import com.limemall.seckill.domain.vo.SeckillResultVO;

public interface ISeckillService {

    /**
     * 秒杀下单：令牌桶限流 -> Redis Lua 原子预扣 -> MQ 异步落库。
     *
     * @return 包含预生成 orderId 的结果，客户端可据此轮询最终状态
     */
    SeckillResultVO seckill(Long activityId);

    /**
     * 查询秒杀结果（客户端轮询）。
     */
    SeckillResultVO queryResult(Long orderId);

    /**
     * 活动详情（含商品信息与 Redis 实时剩余库存）。
     */
    SeckillActivityVO queryActivity(Long activityId);

    /**
     * 缓存预热：把活动配置与库存写入 Redis（活动上线/库存调整后调用）。
     */
    void warmUp(Long activityId);

    /**
     * 支付成功回调：把对应的秒杀订单状态推进为「已支付」。
     * 由 pay.direct 交换机支付成功消息触发，幂等。
     */
    void markPaid(Long orderId);

    /**
     * 对照实现：直接压数据库（悲观锁 + 同步落库），仅用于压测对比，不作为生产链路。
     */
    SeckillResultVO seckillByDatabase(Long activityId);
}
