--[[
  令牌桶限流脚本（按活动维度）
  用「令牌数 + 上次刷新时间」两个字段模拟令牌桶，Lua 保证读取-计算-写回原子性，
  相比单机 Guava RateLimiter，天然支持多实例共享同一限流额度。

  KEYS[1] = seckill:bucket:{activityId}
  ARGV[1] = capacity      桶容量
  ARGV[2] = rate          每秒补充令牌数
  ARGV[3] = now           当前毫秒时间戳
  ARGV[4] = need          本次请求消耗的令牌数

  返回：1 放行 / 0 被限流
]]
local capacity = tonumber(ARGV[1])
local rate = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local need = tonumber(ARGV[4])

local bucket = redis.call('HMGET', KEYS[1], 'tokens', 'ts')
local tokens = tonumber(bucket[1])
local ts = tonumber(bucket[2])
if tokens == nil then
    tokens = capacity
    ts = now
end

local delta = (now - ts) / 1000.0
if delta > 0 then
    tokens = math.min(capacity, tokens + delta * rate)
end

local allowed = 0
if tokens >= need then
    tokens = tokens - need
    allowed = 1
end

redis.call('HMSET', KEYS[1], 'tokens', tokens, 'ts', now)
redis.call('PEXPIRE', KEYS[1], math.ceil(capacity / rate * 1000) + 1000)
return allowed
