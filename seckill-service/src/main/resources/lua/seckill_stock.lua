--[[
  秒杀库存原子预扣脚本
  把「校验库存 / 校验一人一单 / 扣减 / 记录购买用户」四步合成一次原子操作，
  避免高并发下先查后改导致的超卖（Redis 单线程执行 Lua，天然串行）。

  KEYS[1] = seckill:stock:{activityId}   剩余可售库存
  KEYS[2] = seckill:buyers:{activityId}  已下单用户集合
  ARGV[1] = userId

  返回：
     1  预扣成功
     0  已售罄
    -1  重复下单（一人一单）
    -2  活动未预热（缓存不存在）
]]
local stock = redis.call('GET', KEYS[1])
if not stock then
    return -2
end
if tonumber(stock) <= 0 then
    return 0
end
if redis.call('SISMEMBER', KEYS[2], ARGV[1]) == 1 then
    return -1
end
redis.call('DECR', KEYS[1])
redis.call('SADD', KEYS[2], ARGV[1])
return 1
