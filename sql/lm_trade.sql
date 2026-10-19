-- =============================================================
-- 青柠商城 limemall（Spring Cloud Alibaba 版）· 交易库
-- 数据库：`lm_trade`    微服务：trade-service
--
-- 依据：trade-service/src/main/java/com/limemall/trade/domain/po/Order.java
--       trade-service/src/main/java/com/limemall/trade/domain/po/OrderDetail.java
--       trade-service/src/main/java/com/limemall/trade/domain/po/OrderLogistics.java
--       trade-service/src/main/java/com/limemall/trade/service/impl/OrderServiceImpl.java
--       （按 user_id 查订单；total_fee = Σ price * num，单位分；status 1->2）
--
-- 主键说明（严格按 PO，未使用自增）：
--   * `order`.`id`             @TableId(type = IdType.ASSIGN_ID) 雪花算法生成
--   * `order_logistics` 的主键是 `order_id`（@TableId(value="order_id", type=INPUT)，
--     与 `order` 一对一，表中没有 id 列）
--   * `order_detail`.`id`      AUTO_INCREMENT
--
-- 约定：total_fee / price 为 Integer，单位「分」；本库暂无测试数据
--       时间列：DATETIME；create_time 默认 CURRENT_TIMESTAMP，update_time 默认
--       CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP（Java 代码中未设置时间字段，
--       也没有 MetaObjectHandler）；种子数据仍全部写固定字面量，便于复现。
-- =============================================================

SET NAMES utf8mb4;

USE `lm_trade`;

DROP TABLE IF EXISTS `order`;
CREATE TABLE `order` (
  `id`           BIGINT   NOT NULL                COMMENT '订单id（雪花算法生成，非自增）',
  `total_fee`    INT      NOT NULL DEFAULT 0      COMMENT '总金额，单位为分',
  `payment_type` TINYINT  NOT NULL DEFAULT 1      COMMENT '支付类型 1-支付宝 2-微信 3-扣减余额',
  `user_id`      BIGINT   NOT NULL                COMMENT '用户id',
  `status`       TINYINT  NOT NULL DEFAULT 1      COMMENT '订单状态 1-未付款 2-已付款未发货 3-已发货未确认 4-确认收货交易成功 5-交易取消订单关闭 6-交易结束已评价',
  `create_time`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `pay_time`     DATETIME DEFAULT NULL            COMMENT '支付时间',
  `consign_time` DATETIME DEFAULT NULL            COMMENT '发货时间',
  `end_time`     DATETIME DEFAULT NULL            COMMENT '交易完成时间',
  `close_time`   DATETIME DEFAULT NULL            COMMENT '交易关闭时间',
  `comment_time` DATETIME DEFAULT NULL            COMMENT '评价时间',
  `update_time`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_user_id`     (`user_id`),
  KEY `idx_status`      (`status`),
  KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单表';

DROP TABLE IF EXISTS `order_detail`;
CREATE TABLE `order_detail` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '订单详情id',
  `order_id`    BIGINT       NOT NULL                COMMENT '订单id',
  `item_id`     BIGINT       NOT NULL                COMMENT 'sku商品id',
  `num`         INT          NOT NULL DEFAULT 1      COMMENT '购买数量',
  `name`        VARCHAR(200) NOT NULL                COMMENT '商品标题',
  `spec`        VARCHAR(500) DEFAULT NULL            COMMENT '商品动态属性键值集（JSON字符串）',
  `price`       INT          NOT NULL DEFAULT 0      COMMENT '价格，单位：分',
  `image`       VARCHAR(500) DEFAULT NULL            COMMENT '商品图片',
  `create_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_order_id` (`order_id`),
  KEY `idx_item_id`  (`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单详情表';

DROP TABLE IF EXISTS `order_logistics`;
CREATE TABLE `order_logistics` (
  `order_id`          BIGINT       NOT NULL           COMMENT '订单id，与订单表一对一',
  `logistics_number`  VARCHAR(50)  DEFAULT NULL       COMMENT '物流单号',
  `logistics_company` VARCHAR(50)  DEFAULT NULL       COMMENT '物流公司名称',
  `contact`           VARCHAR(50)  DEFAULT NULL       COMMENT '收件人',
  `mobile`            VARCHAR(20)  DEFAULT NULL       COMMENT '收件人手机号码',
  `province`          VARCHAR(50)  DEFAULT NULL       COMMENT '省',
  `city`              VARCHAR(50)  DEFAULT NULL       COMMENT '市',
  `town`              VARCHAR(50)  DEFAULT NULL       COMMENT '区',
  `street`            VARCHAR(255) DEFAULT NULL       COMMENT '街道',
  `create_time`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单物流表';
