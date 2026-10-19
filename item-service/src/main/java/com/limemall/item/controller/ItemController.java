package com.limemall.item.controller;


import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.limemall.common.domain.PageDTO;
import com.limemall.common.domain.PageQuery;
import com.limemall.common.utils.BeanUtils;
import com.limemall.item.domain.dto.ItemDTO;
import com.limemall.item.domain.po.Item;
import com.limemall.item.service.BloomFilterService;
import com.limemall.item.service.IItemService;
import com.limemall.item.service.ItemCacheService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@Api(tags = "商品管理相关接口")
@RestController
@RequestMapping("/items")
@RequiredArgsConstructor
public class ItemController {

    private final IItemService itemService;
    private final ItemCacheService itemCacheService;
    private final BloomFilterService bloomFilterService;

    @ApiOperation("分页查询商品")
    @GetMapping("/page")
    public PageDTO<ItemDTO> queryItemByPage(PageQuery query) {
        // 1.分页查询
        Page<Item> result = itemService.page(query.toMpPage("update_time", false));
        // 2.封装并返回
        return PageDTO.of(result, ItemDTO.class);
    }

    @ApiOperation("根据id批量查询商品（多级缓存 + MGET）")
    @GetMapping
    public List<ItemDTO> queryItemByIds(@RequestParam("ids") List<Long> ids) {
        return itemCacheService.getItems(ids);
    }

    @ApiOperation("根据id查询商品（多级缓存）")
    @GetMapping("{id}")
    public ItemDTO queryItemById(@PathVariable("id") Long id) {
        return itemCacheService.getItem(id);
    }

    @ApiOperation("【压测对照】不走缓存直接查库")
    @GetMapping("/db/{id}")
    public ItemDTO queryItemByIdFromDb(@PathVariable("id") Long id) {
        return BeanUtils.copyBean(itemService.getById(id), ItemDTO.class);
    }

    @ApiOperation("多级缓存统计：各级命中率、回源次数、布隆拦截次数")
    @GetMapping("/cache/stats")
    public Map<String, Object> cacheStats() {
        return itemCacheService.stats();
    }

    @ApiOperation("重建布隆过滤器（批量导入商品后调用）")
    @PostMapping("/cache/bloom/rebuild")
    public void rebuildBloom() {
        bloomFilterService.rebuild();
    }

    @ApiOperation("新增商品")
    @PostMapping
    public void saveItem(@RequestBody ItemDTO item) {
        Item po = BeanUtils.copyBean(item, Item.class);
        itemService.save(po);
        // 新增的商品要加进布隆过滤器，否则会被判定为“一定不存在”
        bloomFilterService.add(po.getId());
    }

    @ApiOperation("更新商品状态")
    @PutMapping("/status/{id}/{status}")
    public void updateItemStatus(@PathVariable("id") Long id, @PathVariable("status") Integer status) {
        Item item = new Item();
        item.setId(id);
        item.setStatus(status);
        itemService.updateById(item);
        // 写库成功后失效缓存（Cache Aside）
        itemCacheService.evict(id);
    }

    @ApiOperation("更新商品")
    @PutMapping
    public void updateItem(@RequestBody ItemDTO item) {
        // 不允许修改商品状态，所以强制设置为null，更新时，就会忽略该字段
        item.setStatus(null);
        // 更新
        itemService.updateById(BeanUtils.copyBean(item, Item.class));
        itemCacheService.evict(item.getId());
    }

    @ApiOperation("根据id删除商品")
    @DeleteMapping("{id}")
    public void deleteItemById(@PathVariable("id") Long id) {
        itemService.removeById(id);
        itemCacheService.evict(id);
    }

    @ApiOperation("批量扣减库存")
    @PutMapping("/stock/deduct")
    public void deductStock(@RequestBody List<com.limemall.item.domain.dto.OrderDetailDTO> items) {
        itemService.deductStock(items);
        // 库存变了，缓存里的库存就不再准确，逐个失效
        for (com.limemall.item.domain.dto.OrderDetailDTO item : items) {
            itemCacheService.evict(item.getItemId());
        }
    }
}
