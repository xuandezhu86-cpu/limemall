package com.limemall.seckill.domain.po;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/**
 * 秒杀订单。
 * id 由服务端预生成（客户端拿 orderId 轮询结果），因此不是自增。
 */
@Data
@Accessors(chain = true)
@TableName("seckill_order")
public class SeckillOrder {

    @TableId(type = IdType.INPUT)
    private Long id;

    private Long activityId;

    private Long userId;

    private Long itemId;

    private Integer num;

    /** 成交价，单位：分 */
    private Integer price;

    /** 0-处理中 1-待支付 2-已支付 3-已取消 9-失败 */
    private Integer status;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;
}
