package com.limemall.seckill.controller;

import com.limemall.seckill.domain.vo.SeckillActivityVO;
import com.limemall.seckill.domain.vo.SeckillResultVO;
import com.limemall.seckill.service.ISeckillService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Api(tags = "秒杀相关接口")
@RestController
@RequestMapping("/seckill")
@RequiredArgsConstructor
public class SeckillController {

    private final ISeckillService seckillService;

    @ApiOperation("秒杀下单（Redis 预扣 + MQ 异步落库）")
    @PostMapping("{activityId}")
    public SeckillResultVO seckill(@PathVariable("activityId") Long activityId) {
        return seckillService.seckill(activityId);
    }

    @ApiOperation("查询秒杀结果（前端轮询）")
    @GetMapping("/result/{orderId}")
    public SeckillResultVO queryResult(@PathVariable("orderId") Long orderId) {
        return seckillService.queryResult(orderId);
    }

    @ApiOperation("查询秒杀活动详情")
    @GetMapping("/activity/{activityId}")
    public SeckillActivityVO queryActivity(@PathVariable("activityId") Long activityId) {
        return seckillService.queryActivity(activityId);
    }

    @ApiOperation("预热活动缓存（上线/调整库存后调用）")
    @PostMapping("/activity/{activityId}/warmup")
    public void warmUp(@PathVariable("activityId") Long activityId) {
        seckillService.warmUp(activityId);
    }

    @ApiOperation("【压测对照】直接压数据库的秒杀实现，请勿用于生产")
    @PostMapping("/legacy/{activityId}")
    public SeckillResultVO seckillByDatabase(@PathVariable("activityId") Long activityId) {
        return seckillService.seckillByDatabase(activityId);
    }
}
