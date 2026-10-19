package com.limemall.seckill.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.limemall.seckill.domain.po.SeckillActivity;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;

public interface SeckillActivityMapper extends BaseMapper<SeckillActivity> {

    /**
     * 扣减持久化库存（带 available_stock >= num 条件，DB 层兜底防超卖）。
     */
    @Update("UPDATE seckill_activity SET available_stock = available_stock - #{num}, update_time = NOW() " +
            "WHERE id = #{activityId} AND available_stock >= #{num}")
    int deductStock(@Param("activityId") Long activityId, @Param("num") int num);

    /**
     * 回补库存（补偿失败订单时使用，不能超过总库存）。
     */
    @Update("UPDATE seckill_activity SET available_stock = available_stock + #{num}, update_time = NOW() " +
            "WHERE id = #{activityId} AND available_stock + #{num} <= total_stock")
    int restoreStock(@Param("activityId") Long activityId, @Param("num") int num);
}
