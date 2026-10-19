package com.limemall.seckill.domain.vo;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 秒杀下单返回：立即返回排队结果，客户端凭 orderId 轮询最终结果。
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@ApiModel(description = "秒杀结果")
public class SeckillResultVO {

    @ApiModelProperty("是否抢到（true 表示已进入排队）")
    private Boolean success;

    @ApiModelProperty("秒杀订单id，用于轮询结果")
    private Long orderId;

    @ApiModelProperty("提示信息")
    private String message;

    @ApiModelProperty("当前剩余库存（Redis 预扣后的值）")
    private Long remainStock;

    public static SeckillResultVO ok(Long orderId, Long remainStock) {
        return new SeckillResultVO(true, orderId, "抢购成功，正在为你生成订单", remainStock);
    }

    public static SeckillResultVO fail(String message, Long remainStock) {
        return new SeckillResultVO(false, null, message, remainStock);
    }
}
