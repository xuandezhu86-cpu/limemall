package com.limemall.seckill.domain.vo;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 秒杀活动详情（含商品信息与实时剩余库存）。
 */
@Data
@ApiModel(description = "秒杀活动详情")
public class SeckillActivityVO {

    private Long id;

    private Long itemId;

    private String title;

    @ApiModelProperty("秒杀价，单位：分")
    private Integer seckillPrice;

    @ApiModelProperty("商品原价，单位：分")
    private Integer originPrice;

    @ApiModelProperty("商品名称")
    private String itemName;

    @ApiModelProperty("商品图片")
    private String itemImage;

    private Integer totalStock;

    @ApiModelProperty("实时剩余库存（取自 Redis 预扣值）")
    private Long remainStock;

    private LocalDateTime startTime;

    private LocalDateTime endTime;

    @ApiModelProperty("是否正在进行中")
    private Boolean ongoing;
}
