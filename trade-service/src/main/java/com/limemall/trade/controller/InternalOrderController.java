package com.limemall.trade.controller;

import com.limemall.api.dto.SeckillOrderDTO;
import com.limemall.trade.service.IOrderService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 服务内部调用接口。
 *
 * <p>路径以 /internal 开头，网关只路由 /orders、/carts、/items、/search、/users、
 * /addresses、/pay-orders、/seckill 这些业务前缀，所以这里的方法对外（浏览器）不可达，
 * 只能由其它微服务通过 Feign 调用。</p>
 */
@Api(tags = "内部接口（仅供服务间调用）")
@RestController
@RequestMapping("/internal/orders")
@RequiredArgsConstructor
public class InternalOrderController {

    private final IOrderService orderService;

    @ApiOperation("秒杀成功后生成交易订单")
    @PostMapping("/seckill")
    public Long createSeckillOrder(@RequestBody SeckillOrderDTO seckillOrderDTO) {
        return orderService.createSeckillOrder(seckillOrderDTO);
    }
}
