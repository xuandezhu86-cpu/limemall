# 青柠商城 LimeMall

一个基于 **Spring Cloud Alibaba** 的电商微服务平台，覆盖商品、搜索、购物车、交易、支付、用户六大业务域，
包含网关鉴权、服务注册发现、分布式事务、消息驱动、缓存与限流等完整的微服务工程实践。

> 项目从单体架构出发（`lm-shop` 模块保留了单体基线），逐步演进为按业务域拆分的微服务架构，
> 完整记录了一次真实的架构演进过程。

## 系统架构

```mermaid
graph TB
    subgraph Client["前端 / 客户端"]
        P["商城门户 (18080)"]
        A["商家后台 (18081)"]
        O["运营后台 (18082)"]
    end

    NG["Nginx 静态资源 + /api 反向代理"]

    subgraph Gateway["接入层"]
        GW["lm-gateway :8080<br/>路由 · JWT 鉴权 · 限流"]
    end

    subgraph Services["业务服务"]
        ITEM["item-service :8081<br/>商品 / 搜索"]
        CART["cart-service :8082<br/>购物车"]
        USER["user-service :8084<br/>用户 / 地址 / 认证"]
        TRADE["trade-service :8085<br/>订单 / 库存扣减"]
        PAY["pay-service :8086<br/>支付"]
    end

    subgraph Infra["基础设施"]
        NACOS["Nacos 2.1<br/>注册中心 + 配置中心"]
        MYSQL["MySQL 8.0<br/>分库存储"]
        REDIS["Redis 7<br/>缓存 / 分布式锁"]
        MQ["RabbitMQ 3.8<br/>异步消息 / 延迟消息"]
        SEATA["Seata 1.5<br/>分布式事务 TC"]
        SENTINEL["Sentinel<br/>流控降级"]
    end

    P --> NG
    A --> NG
    O --> NG
    NG --> GW
    GW --> ITEM
    GW --> CART
    GW --> USER
    GW --> TRADE
    GW --> PAY

    ITEM -.-> NACOS
    CART -.-> NACOS
    USER -.-> NACOS
    TRADE -.-> NACOS
    PAY -.-> NACOS
    GW -.-> NACOS

    ITEM --> MYSQL
    CART --> MYSQL
    USER --> MYSQL
    TRADE --> MYSQL
    PAY --> MYSQL

    CART --> REDIS
    TRADE --> MQ
    PAY --> MQ
    TRADE --> SEATA
    ITEM --> SEATA
    CART --> SENTINEL
```

## 模块说明

| 模块 | 端口 | 职责 | 关键实现 |
|---|---|---|---|
| `lm-gateway` | 8080 | API 网关 | 路由转发、JWT 登录校验、用户信息透传、动态路由（Nacos 配置热更新） |
| `item-service` | 8081 | 商品服务 | 商品 CRUD、分页搜索、Caffeine + Redis 多级缓存 |
| `cart-service` | 8082 | 购物车服务 | 购物车增删改查、Feign 调用商品服务、Sentinel 线程隔离 |
| `user-service` | 8084 | 用户服务 | 登录认证（JWT + RSA）、收货地址、余额扣减 |
| `trade-service` | 8085 | 交易服务 | 下单、订单查询、库存扣减（Seata 全局事务）、订单超时取消（延迟消息） |
| `pay-service` | 8086 | 支付服务 | 支付单管理、余额支付、支付成功消息通知 |
| `seckill-service` | 8087 | 秒杀服务 | Redis + Lua 原子预扣、令牌桶限流、MQ 异步削峰、一人一单、定时对账补偿 |
| `lm-api` | — | 服务间接口契约 | Feign 客户端定义、DTO、降级工厂 |
| `lm-common` | — | 公共组件 | 统一响应、异常处理、用户上下文、拦截器、MQ 配置 |
| `lm-shop` | 8080 | 单体基线版本 | 架构演进前的单体实现，用于对比 |

## 技术栈

- **框架**：Spring Boot 2.7.12、Spring Cloud 2021.0.3、Spring Cloud Alibaba 2021.0.4.0
- **注册/配置**：Nacos 2.1.0（服务发现 + 配置中心，共享配置 `shared-*.yaml`）
- **数据层**：MySQL 8.0.36（按业务域分库）、MyBatis-Plus 3.4.2、HikariCP
- **缓存**：Redis 7
- **消息**：RabbitMQ 3.8（含 `x-delayed-message` 延迟消息插件）
- **分布式事务**：Seata 1.5.2（AT 模式）
- **服务治理**：Sentinel 1.8.6（流控、熔断、线程隔离）
- **网关**：Spring Cloud Gateway + JWT（RSA 签名）
- **文档**：Knife4j / Swagger
- **部署**：Docker Compose 一键起中间件，Nginx 托管前端

## 快速开始

### 1. 环境要求

- JDK 11、Maven 3.6+
- Docker Desktop（WSL2 后端）

### 2. 启动中间件

```bash
docker compose -f infra/docker-compose.yml up -d
```

首次启动会自动建库建表并导入测试数据（`infra/mysql-init/` 挂载到 MySQL 初始化目录）。

### 3. 启动服务

```powershell
# 一键：发布 Nacos 配置 -> 编译 -> 按顺序启动全部微服务
powershell -ExecutionPolicy Bypass -File infra/start-all.ps1
```

或手动：

```bash
mvn -DskipTests clean package
java -jar lm-gateway/target/lm-gateway.jar
```

### 4. 访问

| 入口 | 地址 | 账号 |
|---|---|---|
| 商城门户 | http://localhost:18080 | `jack` / `123` |
| 商家后台 | http://localhost:18081 | `jack` / `123` |
| 运营后台 | http://localhost:18082 | `jack` / `123` |
| Nacos 控制台 | http://localhost:8848/nacos | `nacos` / `nacos` |
| RabbitMQ 控制台 | http://localhost:15672 | `limemall` / `LmMq2026` |
| Sentinel 控制台 | http://localhost:8090 | `sentinel` / `sentinel` |
| Seata 控制台 | http://localhost:7091 | `seata` / `seata` |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | `admin` / `LmGrafana2026` |
| Zipkin | http://localhost:9411 | — |

## 秒杀设计（抗瞬时高并发）

秒杀链路刻意**不追求强一致**，而是用「Redis 预扣 + 异步落库 + 定时对账」换取吞吐能力：

```
请求 → 令牌桶限流(Redis+Lua) → 活动缓存校验 → Lua 原子预扣(库存 + 一人一单) → MQ 投递 → 立即返回 orderId
                                                                                  ↓
                                     消费端幂等落库 → Feign 扣商品真实库存 → 状态置为「待支付」
                                                                                  ↓
                                   定时对账：超时未完成订单重新驱动 / 失败订单回补库存并清理购买记录
```

| 环节 | 做法 | 解决的问题 |
|---|---|---|
| 限流 | Redis + Lua 令牌桶（多实例共享额度） | 把超出处理能力的流量挡在业务逻辑之前 |
| 预扣 | 一个 Lua 脚本内完成「校验库存 + 校验一人一单 + 扣减 + 记录买家」 | 「先查后改」的竞态导致超卖；Lua 在 Redis 中串行执行保证原子性 |
| 削峰 | RabbitMQ 异步落库，消费端按自身节奏处理 | 数据库瞬时写压力被打平 |
| 幂等 | 唯一索引 `uk_activity_user` + 消费前查重 | 消息重复投递造成重复下单 |
| 补偿 | 定时任务重新驱动超时订单、回补库存、校准 Redis 与 DB 库存差异 | MQ 重试耗尽后的数据最终一致 |

**防超卖验证**：执行 `infra/tools/seckill-concurrency-check.ps1`，用 60 个用户并发抢 20 件库存 —— 结果恰好生成 20 笔订单，活动库存与 Redis 库存均归零，无超卖。

## 商品详情多级缓存

商品详情是典型的「读多写少 + 热点集中」场景，item-service 采用 Caffeine + Redis 两级缓存：

```
读：Caffeine(L1) → Redis(L2) → 布隆过滤器 → 互斥锁重建 → DB
写：更新 DB → 删除 L2 → 广播 MQ → 各实例删除自己的 L1（Cache Aside）
```

| 问题 | 处理方式 |
|---|---|
| 缓存穿透（查不存在的数据） | 布隆过滤器（Redis 位图，16M bit，4 个哈希函数）拦截不存在的 id；布隆误判时用「空值缓存」兜底 |
| 缓存击穿（热点 key 失效瞬间） | Redis `SETNX` 互斥锁只放一个线程回源，其余线程短自旋等待；极端情况退化为直接查库保证可用性 |
| 缓存雪崩（大面积同时失效） | L2 过期时间加随机抖动；L1 短 TTL（30s）吸收热点读 |
| 多实例本地缓存不一致 | 更新后通过 fanout 交换机广播失效消息，每个实例一个匿名队列，各自清理 L1 |

**实测结果**（`infra/tools/cache-bench.ps1`，本机 Docker 环境）：

| 指标 | 数值 |
|---|---|
| 商品详情读延迟 | 走缓存 **1.47ms** vs 直连 DB **5.56ms**（冷库场景差距 5~6 倍） |
| 缓存穿透 | 50 次查询不存在的 id：DB 回源 **0 次**（1 次布隆拦截 + 49 次空值缓存命中） |
| 缓存击穿 | 失效后 60 个并发请求：DB 回源 **恰好 1 次**，其余 58 个线程自旋拿到重建结果 |
| 跨实例一致性 | 实例 B 更新价格后，实例 A 立即读到新值（L1 被广播失效） |
| L1 命中率 | 约 0.80（其余为压测用的直连 DB 对照请求与主动失效） |

## 可观测性（指标 + 面板 + 告警）

```
各服务 Actuator + Micrometer ──/actuator/prometheus──▶ Prometheus ──▶ Grafana 面板
   （管理端口 908x，与业务端口隔离）                      │
                                                      └──▶ 7 条告警规则（Prometheus /alerts 可见）
```

- **管理端口与业务端口分离**：Actuator 只监听 `业务端口 + 1000`（网关 9080、商品 9081、购物车 9082、用户 9084、交易 9085、支付 9086、秒杀 9087），业务端口不再暴露任何管理端点。这既是安全实践，也顺带绕开了 springfox 2.10.5 与 Boot 2.6+ 的兼容问题。
- **打开 HTTP 延迟直方图**：`management.metrics.distribution.percentiles-histogram.http.server.requests=true`，否则 Prometheus 只有 count/sum，算不出 P95/P99。
- **自定义业务指标**：商品缓存的 10 个指标（`limemall_cache_l1_hits`、`limemall_cache_db_loads`、`limemall_cache_bloom_rejects` …）直接画进面板，缓存效果一眼可见。

**面板（Grafana，自动 provisioning）**：在线服务数、总 QPS、5xx 速率、缓存回源速率、布隆累计拦截、JVM 堆、各服务 QPS、接口 P95、缓存命中 vs 回源、JVM 堆趋势、HikariCP 活跃/等待连接、MQ 收发速率。

**告警规则**：

| 告警 | 触发条件 | 级别 |
|---|---|---|
| ServiceDown | 实例连续 30s 抓不到指标 | critical |
| HighHttpErrorRate | 5xx 速率 > 0.05/s 持续 1 分钟 | warning |
| SlowApiP95 | 接口 P95 > 500ms 持续 2 分钟 | warning |
| HighJvmHeapUsage | 堆使用率 > 85% 持续 2 分钟 | warning |
| DbConnectionPoolSaturated | 连接池活跃占比 > 80% 持续 2 分钟 | warning |
| CacheHitRateLow | L1 命中率 < 50% 持续 5 分钟 | info |
| CacheHeavyDatabaseFallback | 缓存回源 > 50 次/秒 持续 2 分钟 | info |

**实测数据**（造流量后从 Prometheus 查询）：

| 指标 | 数值 |
|---|---|
| 全站 QPS | 11.1 |
| 接口 P95 | 全站 40.9ms、item-service 4.8ms、seckill-service 87.3ms |
| 商品详情缓存 | 300 次请求 → L1 命中 299 次、回源 DB 0 次 |
| MQ 收发 | 发送 0.34/s、消费 0.34/s（秒杀异步下单链路） |
| 告警状态 | 7 条规则全部 inactive（系统健康） |

## 链路追踪

选型 **Sleuth + Zipkin**：与 Spring Cloud 原生集成、不需要额外探针，本地起一个容器即可。

- 每个服务全量采样（本地演示 `probability: 1.0`，生产建议按比例采样如 0.1）
- **traceId 自动透传**：HTTP 调用（Feign）、RabbitMQ 消息头、线程池任务，跨服务不丢链路
- 日志格式自动带上 `[服务名,traceId,spanId]`，任意服务出问题都能按 traceId 串起全部日志
- Redis 命令（`mget` / `setex` / `getbit`）与 MQ 生产消费（`publish` / `next-message`）也自动纳入链路

**实测：一笔下单请求的完整链路**（Zipkin，24 个 span，端到端 263ms；冷启动首次调用约 2.6s）

| 服务 | Span | 耗时 |
|---|---|---|
| gateway | `POST /orders` (SERVER) | 263.5 ms |
| trade-service | `POST /orders` (SERVER) | 251.6 ms |
| trade-service → item-service | 扣减库存 (CLIENT/SERVER) | 57.6 ms |
| trade-service → cart-service | 清理购物车 (CLIENT/SERVER) | 40.7 ms |
| trade-service | MQ 消费 `on-message` | 56.0 ms |
| item-service | Redis `mget` / `setex` / `getbit` | 4.7 / 3.9 / 2.6 ms |

## 压测与调优

JMeter 5.6.3 非 GUI 模式压测，脚本与原始数据都在 `infra/jmeter/`，完整报告见 **[docs/load-test-report.md](docs/load-test-report.md)**。

**场景一：商品详情读（50 并发 × 30 秒，热点商品）**

| 场景 | 吞吐(TPS) | 平均(ms) | P95 | P99 | 错误率 |
|---|---|---|---|---|---|
| 走多级缓存 `/items/1` | **13,383** | **3.4** | 8 | 31 | 0% |
| 直连数据库 `/items/db/1` | 2,689 | 17.1 | 31 | 50 | 0% |

→ 吞吐 **约 5 倍**，平均延迟降低 **80%**；压测期间 40 万次请求只回源数据库 **3 次**。

**场景二：秒杀下单（200 用户抢 100 件）**

| 场景 | 吞吐(TPS) | 平均(ms) | P95 | P99 | 超卖 |
|---|---|---|---|---|---|
| Redis+Lua 预扣 + MQ 异步 | **105** | **1,442** | 1,846 | 1,896 | 否（恰好 100 单） |
| 数据库悲观锁 + 同步扣库存 | 43.5 | 3,472 | 4,548 | 4,578 | 否（恰好 100 单） |

→ 同等前提下吞吐 **2.4 倍**、延迟降低 **58%**，两套实现都没有超卖。

## 核心接口

```bash
# 登录获取 token
curl -X POST http://localhost:8080/users/login \
     -H "Content-Type: application/json" \
     -d '{"username":"jack","password":"123"}'

# 商品查询（网关放行，无需登录）
curl "http://localhost:8080/items?ids=1,2"
curl "http://localhost:8080/search/list?key=&pageNo=1&pageSize=10"

# 加购物车（需要 token）
curl -X POST http://localhost:8080/carts \
     -H "Content-Type: application/json" -H "authorization: <token>" \
     -d '{"itemId":1,"num":2}'

# 下单（Seata 全局事务：扣库存 + 清购物车 + 建订单）
curl -X POST http://localhost:8080/orders \
     -H "Content-Type: application/json" -H "authorization: <token>" \
     -d '{"addressId":1,"paymentType":3,"details":[{"itemId":1,"num":2}]}'
```

## 目录结构

```
.
├── lm-gateway/          # API 网关
├── lm-api/              # Feign 接口契约
├── lm-common/           # 公共组件
├── item-service/        # 商品服务
├── cart-service/        # 购物车服务
├── user-service/        # 用户服务
├── trade-service/       # 交易服务
├── pay-service/         # 支付服务
├── lm-shop/             # 单体基线版本
├── sql/                 # 建库建表 + 测试数据脚本
├── lm-nginx/html/       # 前端静态资源（门户 / 商家后台 / 运营后台）
└── infra/               # 部署编排：docker-compose、Nacos 配置、启动脚本
```

## 数据库

| 库 | 归属服务 | 表 |
|---|---|---|
| `lm_item` | item-service | `item` |
| `lm_cart` | cart-service | `cart` |
| `lm_user` | user-service | `user`、`address` |
| `lm_trade` | trade-service | `order`、`order_detail`、`order_logistics` |
| `lm_pay` | pay-service | `pay_order` |
| `lm_shop` | 单体基线 | 上述表合并 |

使用 Seata AT 模式的服务（item / cart / trade）各自库中都有 `undo_log` 表。

## 开发记录

- [x] 阶段一：微服务拆分、网关鉴权、Feign 调用、分布式事务、消息驱动
- [x] 阶段二：容器化部署、前端静态资源托管、一键启动脚本
- [x] 阶段三：秒杀服务（Redis + Lua 预扣、令牌桶限流、MQ 异步削峰、一人一单、对账补偿）
- [x] 阶段四：商品详情多级缓存（Caffeine + Redis、击穿/穿透/雪崩治理、跨实例失效广播）
- [x] 阶段五：可观测性（Actuator + Prometheus 指标、Grafana 面板、7 条告警规则、管理端口隔离、Sleuth + Zipkin 链路追踪）
- [x] 阶段六：压测与调优（JMeter 压测脚本 + 真实压测报告，缓存 5 倍吞吐、秒杀 2.4 倍吞吐）

部署与排错细节见 [infra/README.md](infra/README.md)。
