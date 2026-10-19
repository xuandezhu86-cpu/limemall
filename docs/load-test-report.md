# LimeMall 压测报告

> 所有数据均来自本机真实压测（JMeter 5.6.3 非 GUI 模式），没有估算或编造。
> 复现命令见文末「复现方式」。

## 一、测试环境

| 项目 | 配置 |
|---|---|
| 机器 | 单台 Windows 11 开发机，32GB 内存，Docker Desktop (WSL2) |
| 服务进程 | 8 个 JVM（网关 + 6 个业务服务 + 秒杀服务），堆上限 `-Xms256m -Xmx512m` |
| 中间件容器 | MySQL 8.0.36 / Redis 7 / RabbitMQ 3.8 / Nacos 2.1.0 / Seata 1.5.2 / Sentinel 1.8.6 / Nginx / Prometheus / Grafana / Zipkin（共 10 个） |
| 压测工具 | Apache JMeter 5.6.3（非 GUI，`-n -t plan.jmx -l result.jtl`） |
| 压测机 | 与压测目标**同一台机器**（没有独立压力机，客户端会与被压服务抢 CPU/内存） |

> 说明：单机压测的绝对值会明显低于生产环境（客户端、服务、数据库、中间件都在一台机器上），
> 因此本报告的重点是**同一环境下不同实现方案的对比**，而不是绝对 TPS 数字。

## 二、测试脚本

| 文件 | 说明 |
|---|---|
| `infra/jmeter/item-detail.jmx` | 商品详情读压测，`-Jpath` 切换走缓存 `/items/1` 与直连 DB `/items/db/1` |
| `infra/jmeter/seckill.jmx` | 秒杀下单压测，CSV 提供每个线程独立的 JWT token，`-Jpath` 切换优化版与 legacy 版 |
| `infra/tools/make-seckill-tokens.ps1` | 批量造压测用户并登录换取 token，输出 CSV 给 JMeter 使用 |
| `infra/tools/jmeter-report.ps1` | 解析 `.jtl` 结果文件，输出吞吐/延迟分位/错误率对比表 |

## 三、场景一：商品详情读（多级缓存 vs 直连数据库）

**压测参数**：50 并发线程，5 秒 ramp-up，持续 30 秒，访问同一个热点商品（缓存效果最明显的场景）。

| 场景 | 样本数 | 吞吐(TPS) | 平均(ms) | P50 | P95 | P99 | 最大(ms) | 错误率 |
|---|---|---|---|---|---|---|---|---|
| A 走多级缓存 `/items/1` | 400,067 | **13,382.9** | **3.4** | 2 | 8 | 31 | 448 | 0% |
| B 直连数据库 `/items/db/1` | 80,285 | 2,688.8 | 17.1 | 15 | 31 | 50 | 364 | 0% |

**结论**：吞吐 **约 5.0 倍**（13,383 vs 2,689 TPS），平均延迟从 17.1ms 降到 3.4ms（**降低 80%**），P95 从 31ms 降到 8ms。

服务端指标印证（Prometheus，压测期间累计）：

| 指标 | 数值 |
|---|---|
| L1（Caffeine）命中 | 400,046 |
| L1 未命中 | 53 |
| 回源数据库 | 3 |
| L1 命中率 | ≈ 100%（热点商品场景） |

也就是说 40 万次请求只回源了 3 次数据库——**缓存把数据库的读压力几乎完全挡掉了**。

## 四、场景二：秒杀下单（Redis+Lua 预扣 + MQ 异步 vs 直连数据库悲观锁）

**压测参数**：200 个真实登录用户（每人独立 JWT），1 秒内同时发起抢购，活动库存 100 件。
两个方案跑的是同一套业务规则（限购一件、库存不能超卖），只是实现路径不同：

- **优化版**：Redis + Lua 原子预扣 → 一人一单 Set 去重 → 令牌桶限流 → 发 MQ 异步落库（有对账补偿兜底）
- **legacy 版**：`SELECT ... FOR UPDATE` 数据库悲观锁 → 同步插订单 → 同步 Feign 扣商品库存

| 场景 | 样本数 | 吞吐(TPS) | 平均(ms) | P50 | P95 | P99 | 最大(ms) | 错误率 |
|---|---|---|---|---|---|---|---|---|
| C 优化版 `/seckill/1001` | 200 | **105.1** | **1,442** | 1,411 | 1,846 | 1,896 | 1,900 | 0% |
| D legacy `/seckill/legacy/1001` | 200 | 43.5 | 3,472 | 4,263 | 4,548 | 4,578 | 4,591 | 0% |

**正确性校验（两个方案都必须满足）**：

| 校验项 | 优化版 | legacy 版 | 期望 |
|---|---|---|---|
| 生成订单数 | 100 | 100 | = 库存 100 |
| 活动剩余库存 | 0 | 0 | 0 |
| Redis 预扣库存 | 0 | —（不走 Redis） | 0 |
| 一人一单买家数 | 100 | —（靠 DB 唯一索引） | 100 |
| 是否超卖 | 否 | 否 | 否 |

**结论**：在完全相同的前提下，优化版吞吐 **2.4 倍**于数据库悲观锁方案，平均延迟从 3,472ms 降到 1,442ms（**降低 58%**），两个方案都没有超卖。

**为什么差距只有 2.4 倍？**（这一点面试常被追问）

1. 200 个请求是**一次性突发**，优化版的瓶颈在网关 JWT 校验与限流器，而不是 Redis；
2. legacy 版的行锁把 200 个事务串行化，但它的事务很短（本地库操作 + 一次 Feign），所以没有慢到几十倍；
3. 如果库存放大到几千、并发放大到几千，legacy 的锁等待会呈**线性恶化**，而优化版基本恒定（异步削峰）。
   可以这样验证：把 `-Jthreads` 提到 1000、库存提到 1000 再跑一轮。

## 五、压测中发现并修复的问题

| 问题 | 现象 | 处理 |
|---|---|---|
| 直接压 seckill-service（8087）全 500 | 日志 `UnauthorizedException: 请先登录`——秒杀服务依赖网关注入的用户身份 | 压测改走网关（也更接近真实流量），见 `C-seckill.jtl` 里前 200 条的 500 记录 |
| JMeter 参数不生效 | `-JtokensFile=$csv` 被 PowerShell 当成字面量 | 参数加引号 `"-JtokensFile=$csv"` |
| 结果文件混入上一轮数据 | JMeter 的 `.jtl` 是**追加**写入 | 每轮压测前删除旧 `.jtl`，并保留了被污染的原始文件与过滤后的 `C-seckill-ok.jtl` |
| 压测脚本输出乱码 | `.ps1` 里的中文被 PowerShell 5.1 按 GBK 解析 | 脚本统一 ASCII-only（这是本项目的硬性约定） |

## 六、本轮做的调优

| 调优项 | 依据 | 效果 |
|---|---|---|
| JVM 堆上限 `-Xmx512m` | 8 个 JVM 各占约 900MB，机器可用内存一度只剩 2.8GB，服务被 GC 拖到超时 | 可用内存回到 9GB 以上，压测过程中不再出现实例假死 |
| 启动失败自动重试 | 7 个服务同时启动时 Nacos gRPC 连接超时（`Client not connected, current status:STARTING`） | 一键启动成功率从"经常掉 2 个服务"变成稳定全起 |
| 打开 HTTP 延迟直方图 | 默认不导出 bucket，Grafana 的 P95 面板和慢接口告警永远为空 | P95/P99 面板可用，`SlowApiP95` 告警真正生效 |
| 缓存失效广播 + 互斥重建 | 压测前后的一致性校验（见 `infra/tools/cache-bench.ps1`） | 60 并发在缓存失效瞬间只回源 1 次数据库 |

## 七、复现方式

```powershell
$root = "<项目根>"
$jm   = "<工具链>\apache-jmeter-5.6.3\bin\ApacheJMeter.jar"
$env:JAVA_HOME = "<工具链>\jdk\jdk-11.0.32.1+1"

# 场景一：缓存 vs 直连 DB
java -jar $jm -n -t "$root\infra\jmeter\item-detail.jmx" -l A.jtl -Jthreads=50 -Jramp=5 -Jduration=30 -Jport=8081 -Jpath=/items/1
java -jar $jm -n -t "$root\infra\jmeter\item-detail.jmx" -l B.jtl -Jthreads=50 -Jramp=5 -Jduration=30 -Jport=8081 -Jpath=/items/db/1

# 场景二：秒杀（先造用户 token，再把活动库存重置为 100）
powershell -File "$root\infra\tools\make-seckill-tokens.ps1" -Users 200 -Prefix jm -Out "$root\infra\jmeter\seckill-tokens.csv"
java -jar $jm -n -t "$root\infra\jmeter\seckill.jmx" -l C.jtl -Jport=8080 -Jpath=/seckill/1001 -Jthreads=200 -Jramp=1 -Jloops=1 "-JtokensFile=$root\infra\jmeter\seckill-tokens.csv"

# 生成对比表
powershell -File "$root\infra\tools\jmeter-report.ps1" -Files "A.jtl,B.jtl" -Labels "cached,direct-db"
```

## 八、原始数据

`infra/jmeter/results/` 目录下保留了全部原始结果文件与 JMeter 运行日志：

| 文件 | 内容 |
|---|---|
| `A-cached.jtl` / `B-db.jtl` | 场景一原始结果 |
| `C-seckill.jtl` | 场景二优化版（含前 200 条直连服务失败的 500 记录） |
| `C-seckill-ok.jtl` | 场景二优化版（仅 HTTP 200 的有效样本） |
| `D-legacy.jtl` | 场景二 legacy 基线 |
| `table1-cache.md` / `table2-seckill.md` | 对比表（脚本自动生成） |
| `*.log` | JMeter 运行日志 |
