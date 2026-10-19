package com.limemall.item.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.limemall.common.exception.BizIllegalException;
import com.limemall.item.domain.dto.ItemDTO;
import com.limemall.item.domain.dto.OrderDetailDTO;
import com.limemall.item.domain.po.Item;
import com.limemall.item.mapper.ItemMapper;
import com.limemall.item.service.IItemService;
import com.limemall.item.service.ItemCacheService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.List;

/**
 * <p>
 * 商品表 服务实现类
 * </p>
 *
 * @author LimeMall
 */
@Service
@RequiredArgsConstructor
public class ItemServiceImpl extends ServiceImpl<ItemMapper, Item> implements IItemService {

    private final ItemCacheService itemCacheService;

    @Override
    @Transactional
    public void deductStock(List<OrderDetailDTO> items) {
        String sqlStatement = "com.limemall.item.mapper.ItemMapper.updateStock";
        boolean r = false;
        try {
            r = executeBatch(items, (sqlSession, entity) -> sqlSession.update(sqlStatement, entity));
        } catch (Exception e) {
            throw new BizIllegalException("更新库存异常，可能是库存不足!", e);
        }
        if (!r) {
            throw new BizIllegalException("库存不足！");
        }
    }

    @Override
    public List<ItemDTO> queryItemByIds(Collection<Long> ids) {
        // 统一走多级缓存，购物车 / 交易服务的 Feign 调用同样受益
        return itemCacheService.getItems(ids);
    }
}
