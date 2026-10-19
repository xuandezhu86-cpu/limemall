package com.limemall.trade.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.limemall.api.client.CartClient;
import com.limemall.api.client.ItemClient;
import com.limemall.api.dto.ItemDTO;
import com.limemall.api.dto.OrderDetailDTO;
import com.limemall.api.dto.SeckillOrderDTO;
import com.limemall.common.exception.BadRequestException;
import com.limemall.common.utils.UserContext;

import com.limemall.trade.constants.MQConstants;
import com.limemall.trade.domain.dto.OrderFormDTO;
import com.limemall.trade.domain.po.Order;
import com.limemall.trade.domain.po.OrderDetail;
import com.limemall.trade.mapper.OrderMapper;
import com.limemall.trade.service.IOrderDetailService;
import com.limemall.trade.service.IOrderService;
import io.seata.spring.annotation.GlobalTransactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessagePostProcessor;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * <p>
 * 服务实现类
 * </p>
 *
 * @author LimeMall
 * @since 2023-05-05
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OrderServiceImpl extends ServiceImpl<OrderMapper, Order> implements IOrderService {

    private final ItemClient itemClient;
    private final IOrderDetailService detailService;
    private final CartClient cartClient;
    private final RabbitTemplate rabbitTemplate;

    @Override
    @GlobalTransactional
    public Long createOrder(OrderFormDTO orderFormDTO) {
        // 1.订单数据
        Order order = new Order();
        // 1.1.查询商品
        List<OrderDetailDTO> detailDTOS = orderFormDTO.getDetails();
        // 1.2.获取商品id和数量的Map
        Map<Long, Integer> itemNumMap = detailDTOS.stream()
                .collect(Collectors.toMap(OrderDetailDTO::getItemId, OrderDetailDTO::getNum));
        Set<Long> itemIds = itemNumMap.keySet();
        // 1.3.查询商品
        List<ItemDTO> items = itemClient.queryItemByIds(itemIds);
        if (items == null || items.size() < itemIds.size()) {
            throw new BadRequestException("商品不存在");
        }
        // 1.4.基于商品价格、购买数量计算商品总价：totalFee
        int total = 0;
        for (ItemDTO item : items) {
            total += item.getPrice() * itemNumMap.get(item.getId());
        }
        order.setTotalFee(total);
        // 1.5.其它属性
        order.setPaymentType(orderFormDTO.getPaymentType());
        order.setUserId(UserContext.getUser());
        order.setStatus(1);
        // 1.6.将Order写入数据库order表中
        save(order);

        // 2.保存订单详情
        List<OrderDetail> details = buildDetails(order.getId(), items, itemNumMap);
        detailService.saveBatch(details);

        // 3.清理购物车商品
        cartClient.deleteCartItemByIds(itemIds);

        // 4.扣减库存
        try {
            itemClient.deductStock(detailDTOS);
        } catch (Exception e) {
            throw new RuntimeException("库存不足！");
        }

        //
        rabbitTemplate.convertAndSend(
                MQConstants.DELAY_EXCHANGE_NAME,
                MQConstants.DELAY_ORDER_KEY,
                order.getId(),
                message -> {
                    message.getMessageProperties().setDelay(10000);
                    return message;
                });

        return order.getId();
    }

    /**
     * 秒杀成功后生成交易订单。
     *
     * <p>与普通下单的差异（都是有意为之）：</p>
     * <ul>
     *   <li>价格取秒杀价，不再按商品当前价计算；</li>
     *   <li>不扣库存：商品库存已由秒杀服务在异步落库时扣减，这里再扣会扣两次；</li>
     *   <li>不动购物车：秒杀绕过购物车直接成单；</li>
     *   <li>订单号由秒杀服务生成并传进来，两边用同一个 id，用户凭这个订单号即可支付。</li>
     * </ul>
     * 幂等：MQ 重试或对账补偿可能重复调用，订单已存在时直接返回。
     */
    @Override
    @Transactional
    public Long createSeckillOrder(SeckillOrderDTO dto) {
        Order exist = getById(dto.getOrderId());
        if (exist != null) {
            log.info("[秒杀转单] 订单已存在，幂等返回 orderId={}", dto.getOrderId());
            return exist.getId();
        }
        // 1.查商品信息，仅用于订单详情的名称/规格/图片
        List<ItemDTO> items = itemClient.queryItemByIds(Collections.singleton(dto.getItemId()));
        ItemDTO item = items.isEmpty() ? null : items.get(0);

        // 2.写订单（状态 1=待支付）
        LocalDateTime now = LocalDateTime.now();
        Order order = new Order()
                .setId(dto.getOrderId())
                .setUserId(dto.getUserId())
                .setTotalFee(dto.getPrice() * dto.getNum())
                .setPaymentType(3)
                .setStatus(1)
                .setCreateTime(now)
                .setUpdateTime(now);
        save(order);

        // 3.写订单详情
        OrderDetail detail = new OrderDetail()
                .setOrderId(order.getId())
                .setItemId(dto.getItemId())
                .setNum(dto.getNum())
                .setPrice(dto.getPrice())
                .setName(item == null ? null : item.getName())
                .setSpec(item == null ? null : item.getSpec())
                .setImage(item == null ? null : item.getImage())
                .setCreateTime(now)
                .setUpdateTime(now);
        detailService.save(detail);

        // 4.延迟消息：超时未支付自动取消（与普通下单一致）
        rabbitTemplate.convertAndSend(
                MQConstants.DELAY_EXCHANGE_NAME,
                MQConstants.DELAY_ORDER_KEY,
                order.getId(),
                message -> {
                    message.getMessageProperties().setDelay(10000);
                    return message;
                });
        log.info("[秒杀转单] 生成交易订单成功 orderId={}, userId={}, itemId={}, totalFee={}",
                order.getId(), dto.getUserId(), dto.getItemId(), order.getTotalFee());
        return order.getId();
    }

    @Override
    public void markOrderPaySuccess(Long orderId) {
        // 1.查询订单
        Order old = getById(orderId);
        // 2.判断订单状态
        if (old == null || old.getStatus() != 1) {
            // 订单不存在或者订单状态不是1，放弃处理
            return;
        }
        // 3.尝试更新订单
        Order order = new Order();
        order.setId(orderId);
        order.setStatus(2);
        order.setPayTime(LocalDateTime.now());
        updateById(order);
    }

    private List<OrderDetail> buildDetails(Long orderId, List<ItemDTO> items, Map<Long, Integer> numMap) {
        List<OrderDetail> details = new ArrayList<>(items.size());
        for (ItemDTO item : items) {
            OrderDetail detail = new OrderDetail();
            detail.setName(item.getName());
            detail.setSpec(item.getSpec());
            detail.setPrice(item.getPrice());
            detail.setNum(numMap.get(item.getId()));
            detail.setItemId(item.getId());
            detail.setImage(item.getImage());
            detail.setOrderId(orderId);
            details.add(detail);
        }
        return details;
    }

    @Override
    public void cancelOrder(Long orderId) {
        // todo
    }
}
