package com.limemall.trade.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.limemall.api.dto.SeckillOrderDTO;
import com.limemall.trade.domain.dto.OrderFormDTO;
import com.limemall.trade.domain.po.Order;


/**
 * <p>
 *  服务类
 * </p>
 *
 * @author LimeMall
 * @since 2023-05-05
 */
public interface IOrderService extends IService<Order> {

    Long createOrder(OrderFormDTO orderFormDTO);

    /**
     * 秒杀成功后生成交易订单（价格取秒杀价、不扣库存、不动购物车），幂等。
     */
    Long createSeckillOrder(SeckillOrderDTO seckillOrderDTO);

    void markOrderPaySuccess(Long orderId);

    void cancelOrder(Long orderId);
}
