package com.limemall.item.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.limemall.item.domain.dto.ItemDTO;
import com.limemall.item.domain.dto.OrderDetailDTO;
import com.limemall.item.domain.po.Item;
import java.util.Collection;
import java.util.List;

/**
 * <p>
 * 商品表 服务类
 * </p>
 *
 * @author LimeMall
 * @since 2023-05-05
 */
public interface IItemService extends IService<Item> {

    void deductStock(List<OrderDetailDTO> items);

    List<ItemDTO> queryItemByIds(Collection<Long> ids);
}
