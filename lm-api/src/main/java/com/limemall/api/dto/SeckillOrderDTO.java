package com.limemall.api.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.experimental.Accessors;

/**
 * 秒杀成功后创建交易订单的请求参数（服务内部调用，不经过网关）。
 *
 * <p>秒杀是「Redis 预扣 + MQ 异步落库」，商品库存由秒杀服务扣减，
 * 这里只负责把订单写进交易库，让用户能走正常的支付流程，因此：
 * 价格用秒杀价（不再按商品当前价计算）、不再扣库存、不动购物车。</p>
 *
 * @author LimeMall
 */
@Data
@Accessors(chain = true)
@ApiModel(description = "秒杀转交易订单请求")
public class SeckillOrderDTO {

    @ApiModelProperty("订单id：秒杀服务生成的雪花id，交易订单复用同一个id，便于用户凭订单号支付")
    private Long orderId;

    @ApiModelProperty("下单用户id")
    private Long userId;

    @ApiModelProperty("商品id")
    private Long itemId;

    @ApiModelProperty("购买数量")
    private Integer num;

    @ApiModelProperty("成交单价（分），即秒杀价")
    private Integer price;
}
