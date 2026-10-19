package com.limemall.seckill.domain.po;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/**
 * 秒杀活动。
 */
@Data
@Accessors(chain = true)
@TableName("seckill_activity")
public class SeckillActivity {

    /** 活动id（雪花算法生成） */
    @TableId(type = IdType.INPUT)
    private Long id;

    /** 秒杀商品id */
    private Long itemId;

    /** 活动标题 */
    private String title;

    /** 秒杀价，单位：分 */
    private Integer seckillPrice;

    /** 总库存 */
    private Integer totalStock;

    /** 可售库存（由消费端扣减，是持久化的权威值） */
    private Integer availableStock;

    /** 开始时间 */
    private LocalDateTime startTime;

    /** 结束时间 */
    private LocalDateTime endTime;

    /** 状态 0-停用 1-启用 */
    private Integer status;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;

    /** 当前是否在活动时间窗口内且已启用 */
    public boolean isOngoing() {
        LocalDateTime now = LocalDateTime.now();
        return status != null && status == 1
                && startTime != null && endTime != null
                && !now.isBefore(startTime) && !now.isAfter(endTime);
    }
}
