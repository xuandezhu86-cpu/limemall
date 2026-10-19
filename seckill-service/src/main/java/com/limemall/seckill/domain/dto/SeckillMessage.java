package com.limemall.seckill.domain.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;

/**
 * 秒杀下单消息：Redis 预扣成功后投递，由消费端异步落库并扣真实库存。
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class SeckillMessage implements Serializable {

    private static final long serialVersionUID = 1L;

    /** 预生成的秒杀订单id */
    private Long orderId;

    private Long activityId;

    private Long userId;

    private Long itemId;

    /** 秒杀价，单位：分 */
    private Integer price;

    private Integer num;
}
