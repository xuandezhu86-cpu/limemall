package com.limemall.api.client;


import com.limemall.api.dto.SeckillOrderDTO;
import io.swagger.annotations.ApiImplicitParam;
import io.swagger.annotations.ApiOperation;
import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.PutMapping;

@FeignClient(value = "trade-service")
public interface TradeClient {

    @PutMapping("/orders/{orderId}")
    void markOrderPaySuccess(@PathVariable("orderId") Long orderId);

    /**
     * 秒杀成功后生成交易订单（内部接口，网关没有 /internal 路由，外部访问不到）。
     * 幂等：订单号已存在时直接返回。
     */
    @PostMapping("/internal/orders/seckill")
    Long createSeckillOrder(@RequestBody SeckillOrderDTO seckillOrderDTO);
}
