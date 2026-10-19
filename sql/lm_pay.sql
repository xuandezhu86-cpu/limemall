-- =============================================================
-- 青柠商城 limemall（Spring Cloud Alibaba 版）· 支付库
-- 数据库：`lm_pay`    微服务：pay-service
--
-- 依据：pay-service/src/main/java/com/limemall/pay/domain/po/PayOrder.java
--       pay-service/src/main/java/com/limemall/pay/service/impl/PayOrderServiceImpl.java
--       （queryByBizOrderNo：按 biz_order_no 查询且 .one()；
--         lambdaUpdate 按 id + status 更新支付状态）
--       pay-service/src/main/java/com/limemall/pay/controller/PayController.java
--       （按 biz_order_no 查询支付单）
--       pay-service/src/main/java/com/limemall/pay/enums/PayChannel.java
--       pay-service/src/main/java/com/limemall/pay/enums/PayType.java
--       pay-service/src/main/java/com/limemall/pay/enums/PayStatus.java
--
-- 字段取值（重点，这三个字段在 PO 里是 String/Integer，不是 @EnumValue 枚举）：
--   pay_channel_code VARCHAR：存 PayChannel 的枚举名，前端传值
--       aliPay=支付宝支付 / wxPay=微信支付 / balance=余额支付
--       （PayChannel.valueOf(value) 决定了库里存的是枚举名字符串）
--   pay_type   TINYINT：存 PayType.getValue()
--       1=网页支付JS 2=小程序支付 3=APP支付 4=扫码支付 5=余额支付
--   status     TINYINT：存 PayStatus.getValue()
--       0=未提交 1=待支付 2=支付超时或取消(已关闭) 3=支付成功
--   is_delete  Boolean -> TINYINT(1)：0-未删除 1-已删除
--
-- 主键：@TableId(type = IdType.ASSIGN_ID)，雪花算法生成，故 id 不自增
-- 约定：amount 为 Integer，单位「分」；expand_json 为 JSON 字符串（PO 是 String -> VARCHAR）
--       本库暂无测试数据
--       时间列：DATETIME；create_time 默认 CURRENT_TIMESTAMP，update_time 默认
--       CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP（Java 代码中未设置时间字段，
--       也没有 MetaObjectHandler）；种子数据仍全部写固定字面量，便于复现。
-- =============================================================

SET NAMES utf8mb4;

USE `lm_pay`;

DROP TABLE IF EXISTS `pay_order`;
CREATE TABLE `pay_order` (
  `id`               BIGINT        NOT NULL                COMMENT '支付单id（雪花算法生成，非自增）',
  `biz_order_no`     BIGINT        NOT NULL                COMMENT '业务订单号（交易库 order.id）',
  `pay_order_no`     BIGINT        DEFAULT NULL            COMMENT '支付单号',
  `biz_user_id`      BIGINT        DEFAULT NULL            COMMENT '支付用户id',
  `pay_channel_code` VARCHAR(30)   DEFAULT NULL            COMMENT '支付渠道编码 aliPay/wxPay/balance',
  `amount`           INT           NOT NULL DEFAULT 0      COMMENT '支付金额，单位：分',
  `pay_type`         TINYINT       DEFAULT NULL            COMMENT '支付类型 1-网页支付JS 2-小程序 3-APP 4-扫码 5-余额支付',
  `status`           TINYINT       NOT NULL DEFAULT 0      COMMENT '支付状态 0-待提交 1-待支付 2-支付超时或取消 3-支付成功',
  `expand_json`      VARCHAR(1000) DEFAULT NULL            COMMENT '拓展字段，用于传递不同渠道单独处理的字段',
  `result_code`      VARCHAR(50)   DEFAULT NULL            COMMENT '第三方返回业务码',
  `result_msg`       VARCHAR(255)  DEFAULT NULL            COMMENT '第三方返回提示信息',
  `pay_success_time` DATETIME      DEFAULT NULL            COMMENT '支付成功时间',
  `pay_over_time`    DATETIME      DEFAULT NULL            COMMENT '支付超时时间',
  `qr_code_url`      VARCHAR(500)  DEFAULT NULL            COMMENT '支付二维码链接',
  `create_time`      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time`      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `creater`          BIGINT        DEFAULT NULL            COMMENT '创建人',
  `updater`          BIGINT        DEFAULT NULL            COMMENT '更新人',
  `is_delete`        TINYINT(1)    NOT NULL DEFAULT 0      COMMENT '逻辑删除 0-未删除 1-已删除',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_biz_order_no` (`biz_order_no`),
  UNIQUE KEY `uk_pay_order_no` (`pay_order_no`),
  KEY `idx_biz_user_id` (`biz_user_id`),
  KEY `idx_status`      (`status`),
  KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='支付订单表';
