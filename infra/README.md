# limemall 本地运行手册

> 本机（Windows 10/11 + Docker Desktop）已经把《青柠商城 limemall》完整跑起来了。
> 这份文档说明**现在怎么用**、**我改了什么**、**出问题怎么查**、**换机器怎么复现**。

---

## 一、现在已经跑起来了：访问地址与账号

| 入口 | 地址 | 账号 |
|---|---|---|
| 商城门户（前端） | http://localhost:18080 | `jack` / `123`（也可用 `Rose` / `123`） |
| 商城后台 | http://localhost:18081 | 同上 |
| 运营后台 | http://localhost:18082 | 同上 |
| 网关（所有接口入口） | http://localhost:8080 | 需登录后带 `authorization` 头 |
| Nacos 控制台 | http://localhost:8848/nacos | `nacos` / `nacos` |
| RabbitMQ 管理台 | http://localhost:15672 | `limemall` / `LmMq2026` |
| Sentinel 控制台 | http://localhost:8090 | `sentinel` / `sentinel` |
| Seata 控制台 | http://localhost:7091 | `seata` / `seata` |
| **Prometheus**（指标与告警） | http://localhost:9090 | — |
| **Grafana**（监控面板） | http://localhost:3000 | `admin` / `LmGrafana2026` |
| **Zipkin**（链路追踪） | http://localhost:9411 | — |

> 各服务的 Actuator 指标在**管理端口**（业务端口 + 1000）：网关 9080、商品 9081、购物车 9082、用户 9084、交易 9085、支付 9086、秒杀 9087，例如 http://localhost:9081/actuator/prometheus 。业务端口上不暴露管理端点。
> 需要起**第二个实例**时用 `run-service.ps1 <模块名> -Port <端口>`，脚本会同时把管理端口派生成 `<端口>+1000`，否则第二个实例会因为管理端口被占用而启动失败。

验证过的完整链路：登录 → 搜索/商品 → 加购物车 → 下单（Feign + Seata AT 全局事务，扣库存、清购物车）→ 申请支付 → 余额支付（扣余额）→ MQ 通知交易服务把订单改为「已付款」。

---

## 二、日常启停

```powershell
# 一键启动（会自动拉起 Docker Desktop、起容器、发 Nacos 配置、按顺序起 7 个服务，失败会自动重试一轮）
powershell -ExecutionPolicy Bypass -File "<项目根>\infra\start-all.ps1"

# 只停 Java 服务（容器继续跑，数据不丢）
powershell -ExecutionPolicy Bypass -File "<项目根>\infra\stop-all.ps1"

# 连容器一起停（数据卷保留）
powershell -ExecutionPolicy Bypass -File "<项目根>\infra\stop-all.ps1" -All

# 单独起/重启某个服务（把 <模块名> 换成 lm-gateway / item-service / cart-service / user-service / trade-service / pay-service / seckill-service）
powershell -ExecutionPolicy Bypass -File "<项目根>\infra\run-service.ps1" <模块名>
```

> 重启单个服务的正确姿势：先 `stop-all.ps1` 停掉（或按端口杀进程），再 `run-service.ps1` 起。
> 服务日志在 `<项目根>\<模块名>\logs\<服务名>\spring.log`。
> 脚本默认给 JVM 加 `-Xms256m -Xmx512m`（一台机器要跑 8~10 个 JVM，不限制堆会被压到换页），可用 `$env:LM_JAVA_OPTS` 覆盖。

---

## 三、目录结构

```
<项目根>\                         （仓库根目录，即 git 仓库所在处）
├─ pom.xml                        Maven 聚合工程
├─ lm-gateway/ lm-api/ lm-common/ 网关 / 服务契约 / 公共组件
├─ item-service/ cart-service/ user-service/ trade-service/ pay-service/ seckill-service/
├─ lm-shop/                       单体基线版本（与网关同占 8080，不能同时起）
├─ sql/                           建库/建表/测试数据脚本
├─ lm-nginx/html/                 前端静态资源（门户 / 商家后台 / 运营后台）
└─ infra/                         部署编排
   ├─ docker-compose.yml          MySQL / Nacos / RabbitMQ / Redis / Seata / Sentinel / Nginx / Prometheus / Grafana / Zipkin
   ├─ mysql-init/                 容器首次启动自动执行的 SQL（含 nacos 建表）
   ├─ nacos-configs/              需要发布到 Nacos 的配置
   ├─ rabbitmq/                   自定义 MQ 镜像（带延迟消息插件）
   ├─ seata/ nginx/               Seata Server 与容器版 nginx 配置
   ├─ prometheus/                 抓取配置 + 告警规则（prometheus.yml / alert-rules.yml）
   ├─ grafana/                    数据源、面板 provisioning 与总览面板 JSON
   ├─ tools/                      辅助脚本（品牌图生成、缓存验证 cache-bench.ps1、秒杀并发校验 seckill-concurrency-check.ps1）
   ├─ start-all.ps1 / stop-all.ps1 / run-service.ps1
   └─ README.md                   本文档

<项目根的上级>\tools\              JDK 11 + Maven 3.9.9 + settings.xml（工具链放在仓库外，不入库）
```

---

## 四、中间件（Docker，compose 项目名 `lm-infra`）

| 容器 | 镜像 | 端口 | 说明 |
|---|---|---|---|
| lm-mysql | mysql:8.0.36 | 3306 | root / `123`，utf8mb4，`mysql_native_password` |
| lm-nacos | nacos/nacos-server:v2.1.0-slim | 8848、9848、9849 | standalone，配置持久化在 MySQL 的 `nacos` 库 |
| lm-mq | limemall/rabbitmq-delayed:3.8（本地构建） | 5672、15672 | 用户 `limemall`/`LmMq2026`，vhost **`/limemall`**，自带 `x-delayed-message` 插件 |
| lm-redis | redis:7 | **6381**（宿主）→ 6379 | 宿主机 6379/6380 已被另一个项目占用，故映射 6381 |
| lm-seata | seataio/seata-server:1.5.2 | 8091、7091 | 注册到 Nacos，事务组 `limemall` → 集群 `default` |
| lm-sentinel | bladex/sentinel-dashboard:1.8.6 | 8090 | 控制台 |
| lm-nginx | nginx:1.22 | 80、18080、18081、18082 | 挂载项目里的 `lm-nginx\html`，`/api` 反代到网关 |
| lm-prometheus | prom/prometheus:v2.51.2 | 9090 | 抓取各服务 `/actuator/prometheus`，加载 7 条告警规则 |
| lm-grafana | grafana/grafana:10.4.2 | 3000 | 数据源与面板自动 provisioning（`infra\grafana`） |
| lm-zipkin | openzipkin/zipkin:3.3.0 | 9411 | 链路数据内存存储，重启后清空 |

---

## 五、数据库

| 库 | 归属服务 | 表 |
|---|---|---|
| `lm_item` | item-service | `item`(24 条商品)、`undo_log` |
| `lm_cart` | cart-service | `cart`、`undo_log` |
| `lm_trade` | trade-service | `order`、`order_detail`、`order_logistics`、`undo_log` |
| `lm_user` | user-service | `user`(jack/Rose)、`address` |
| `lm_pay` | pay-service | `pay_order` |
| `limemall` | 单体版 lm-shop | 上面 8 张表合并 |
| `nacos` | Nacos | 配置中心自带 12 张表 |

- 脚本位置：`hmall-master\sql\`（`00-create-databases.sql` → 各库 → `02-undo-log.sql`）。
- 测试账号密码是 BCrypt 哈希（明文 `123`），用 Spring Security 的 `BCryptPasswordEncoder` 生成并写入。
- 金额列（`price`/`total_fee`/`balance`/`amount`）**单位是分**（Integer）。

---

## 六、服务清单与启动顺序

| 模块 | 端口 | 管理端口 | Nacos 服务名 | 依赖 |
|---|---|---|---|---|
| lm-gateway | 8080 | 9080 | gateway | Nacos（路由来自 Nacos 的 `gateway-routes.json`）、`limemall.jks` |
| item-service | 8081 | 9081 | item-service | MySQL `lm_item`、Redis(6381)、RabbitMQ、Nacos、Seata |
| cart-service | 8082 | 9082 | cart-service | MySQL `lm_cart`、Nacos、Seata、Sentinel |
| user-service | 8084 | 9084 | user-service | MySQL `lm_user`、Nacos |
| trade-service | 8085 | 9085 | trade-service | MySQL `lm_trade`、Nacos、Seata、RabbitMQ |
| pay-service | 8086 | 9086 | pay-service | MySQL `lm_pay`、Nacos、RabbitMQ |
| seckill-service | 8087 | 9087 | seckill-service | MySQL `lm_seckill`、Redis(6381)、RabbitMQ、Nacos |
| lm-shop（单体版，**与网关同占 8080，不能同时起**） | 8080 | 9089 | — | MySQL `limemall`、Redis(6381) |

启动顺序：MySQL/Nacos 就绪 → gateway → 各业务服务（`start-all.ps1` 已按此顺序处理）。

---

## 七、为了让项目跑起来，我改了/加了什么

1. **补全被抹成 `***` 的配置（23 个 yaml）**
   - 4 个 `bootstrap.yaml` 的 `spring.cloud.nacos.server-addr` → `localhost:8848`
   - 各服务 `application-dev.yaml` / `-local.yaml`：`lm.db.host: localhost`、`lm.db.pw: "LmDb2026"`
   - `user-service` / `pay-service` / `lm-shop` 的 `application.yaml`：库名（`lm_user`/`lm_pay`/`limemall`）、`username: root`
   - JWT：`alias: limemall`、`password: limemall123`（用 keytool 验证过 `limemall.jks` 里只有别名 `limemall`）
   - RabbitMQ：`localhost:5672`、`virtual-host: /limemall`、`limemall` / `LmMq2026`
   - `lm-shop` 追加 `spring.redis.port: 6381`
2. **新增 `hmall-master\sql\`**：按 PO/枚举类/自定义 Mapper SQL 逆向生成的建表脚本 + 测试数据（商品 24 条、用户/地址、BCrypt 密码）。
3. **Nacos 配置 6 份**：`shared-jdbc` / `shared-log` / `shared-swagger` / `shared-seata` / `cart-service` / `gateway-routes.json`。
   ⚠️ 课程笔记里购物车上限写的是 `lm.cart.maxAmount`，但代码里 `CartProPerties` 的字段是 **`maxItems`**，写成 `maxAmount` 会在加购时报 NPE，已修正。
4. **RabbitMQ vhost 是 `/limemall`（带斜杠）**，不是 `limemall`；另需 `x-delayed-message` 插件（官方镜像不带），已用 `infra\rabbitmq\Dockerfile` 打进自定义镜像。
5. **Seata 客户端改用 file 注册 + `grouplist: 127.0.0.1:8091`**：容器注册到 Nacos 的是容器内网 IP（172.x），宿主机路由不到，直连映射端口最稳。
6. **nginx 用容器跑**：Windows 版 `nginx.exe` 读不了含中文的路径（`CreateFile() failed (1113: No mapping for the Unicode character ...)`）。
7. 三个使用 Seata 的库补了 **`undo_log`** 表，`lm_cart.cart.name` 改为可空（代码插入购物车时不写 name，否则报 `Field 'name' doesn't have a default value`）。

---

## 八、常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 启动报 `no available service 'default' found` | Seata 没起或 grouplist 不对；确认 `lm-seata` 容器在跑、8091 可连 |
| 加购/下单报 `undo_log doesn't exist` | 对应库缺 `undo_log`，执行 `sql\02-undo-log.sql` |
| 订单支付后状态不变 | trade-service 的 MQ 监听容器可能因早期报错停了，重启 trade-service |
| MQ 报 `unknown exchange type 'x-delayed-message'` | MQ 镜像没带插件，用 `docker compose up -d --build rabbitmq` |
| MQ 报 `vhost /limemall not found` | `docker exec lm-mq rabbitmqctl add_vhost "/limemall"` + `set_permissions -p "/limemall" limemall ".*" ".*" ".*"` |
| 想跑单体版 lm-shop | 先停掉 gateway（8080 冲突）：`stop-all.ps1` 再 `run-service.ps1 lm-shop` |
| 端口被占 | `Get-NetTCPConnection -LocalPort <端口> -State Listen` 找到 PID 后 `Stop-Process -Id <pid> -Force` |
| 改了 Nacos 配置不生效 | 大部分服务重启后生效（`cart-service.yaml` 这类支持动态刷新） |
| Docker 拉不动镜像 | `C:\Users\Admin\.docker\daemon.json` 已配国内镜像源；必要时 `docker compose up -d --build` 重试 |
| 加了 Actuator 后服务启动报 `documentationPluginsBootstrapper` NPE | springfox 2.10.5 处理不了 Boot 2.6+ 的 `PathPatternParser` 与 Actuator 端点映射。只加 `spring.mvc.pathmatch.matching-strategy=ant_path_matcher` 不够，本项目用「管理端口与业务端口分离」彻底绕开（Actuator 落在 management 子上下文） |
| `lm-common` 编译报找不到 `ObjectMapper` | `jackson-dataformat-xml` 是 `provided` 作用域，传递依赖被 Maven 丢弃；已在 pom 里显式声明 `jackson-databind` |
| Grafana 的 P95 面板没数据、慢接口告警不触发 | Boot 2.x 默认不导出 HTTP 延迟直方图，需 `management.metrics.distribution.percentiles-histogram.http.server.requests=true` |
| 服务起来一会儿又自己没了 | 多半是内存被压垮（多个 JVM + Docker）。确认 `run-service.ps1` 的堆上限生效，或 `Get-CimInstance Win32_OperatingSystem` 看可用内存 |
| 起第二个实例报 `Web server failed to start. Port 9081 was already in use` | 管理端口写死在配置里，第二个实例会和第一个撞端口。用 `run-service.ps1 item-service -Port 8088`，脚本会同时把管理端口派生成 9088 |
| 想看某个服务日志 | `<项目根>\<模块>\logs\<服务名>\spring.log` |

---

## 九、换机器从零复现

1. 装 Docker Desktop（WSL2 后端）、JDK 11、Maven 3.9+（或直接拷贝本目录的 `tools\`）。
2. 把本目录（`hmall-2\`）整体拷过去，路径**尽量不含中文**（Java/Maven 没问题，Windows 版 nginx 会踩坑）。
3. `docker compose -f infra\docker-compose.yml up -d`（首次会自动建库建表导数据，因为 `infra\mysql-init` 挂在 `/docker-entrypoint-initdb.d`）。
4. 等 Nacos 起来后，跑 `infra\start-all.ps1`（它会自动发布 Nacos 配置、编译、按顺序启动服务）。
5. 浏览器打开 http://localhost:18080 ，用 `jack` / `123` 登录。

---

## 十、接口冒烟命令（可直接复制）

```powershell
# 登录拿 token
curl.exe -s -X POST "http://localhost:8080/users/login" -H "Content-Type: application/json" -d '{\"username\":\"jack\",\"password\":\"123\"}'

# 商品（网关放行，无需 token）
curl.exe -s "http://localhost:8080/items?ids=1,2"
curl.exe -s "http://localhost:8080/search/list?key=&pageNo=1&pageSize=5"

# 带 token 访问购物车（把 <TOKEN> 换成上一步返回的 token）
curl.exe -s "http://localhost:8080/carts" -H "authorization: <TOKEN>"
```

---

## 十一、可观测性怎么用

**① 指标（Prometheus + Grafana）**

```powershell
# 看某个服务的原始指标
curl.exe -s "http://localhost:9081/actuator/prometheus" | Select-String "limemall_cache"

# 确认抓取目标都健康（应全部 up）
curl.exe -s "http://localhost:9090/api/v1/targets"

# 看告警规则当前状态（firing / pending / inactive）
curl.exe -s "http://localhost:9090/api/v1/rules"

# 直接查一个指标（示例：商品缓存回源速率）
curl.exe -s "http://localhost:9090/api/v1/query?query=sum(rate(limemall_cache_db_loads[1m]))"
```

- Grafana 面板「LimeMall 服务总览」已自动 provisioning（12 个面板），改 `infra\grafana\dashboards\*.json` 后 30 秒内自动重载。
- 缓存效果验证脚本：`infra\tools\cache-bench.ps1`（延迟对比、穿透、击穿、跨实例一致性）。
- 秒杀并发校验脚本：`infra\tools\seckill-concurrency-check.ps1 -Users 60 -Stock 20`。

**② 链路追踪（Zipkin）**

```powershell
# 已上报的服务列表
curl.exe -s "http://localhost:9411/api/v2/services"

# 查某个服务最近的链路（lookback 单位毫秒）
curl.exe -s "http://localhost:9411/api/v2/traces?serviceName=trade-service&limit=5&lookback=300000"
```

浏览器打开 http://localhost:9411 ，选服务名后点 `RUN QUERY` 即可看到瀑布图；点进任意 trace 能看到跨服务、Redis 命令、MQ 生产消费的完整调用树。日志里也带了 `[服务名,traceId,spanId]`，可直接按 traceId 检索。

