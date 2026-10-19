-- =============================================================
-- 青柠商城 LimeMall · 秒杀库
-- 数据库：`lm_seckill`    微服务：seckill-service
--
-- 设计说明：
--   * seckill_activity 保存活动与库存（available_stock 是持久化的可售库存，
--     Redis 中的 seckill:stock:{id} 是预扣后的剩余量，最终以消费端扣减为准）
--   * seckill_order.id 由雪花算法预生成（客户端拿到 orderId 后轮询结果），故不自增
--   * uk_activity_user 唯一索引是"一人一单"的最终兜底（Redis Set 是第一道拦截）
--   * status: 0-处理中(已预扣，等待落库) 1-待支付 2-已支付 3-已取消 9-失败(需补偿)
-- =============================================================

SET NAMES utf8mb4;

USE `lm_seckill`;

DROP TABLE IF EXISTS `seckill_activity`;
CREATE TABLE `seckill_activity` (
  `id`              BIGINT       NOT NULL                COMMENT '活动id（雪花算法生成）',
  `item_id`         BIGINT       NOT NULL                COMMENT '秒杀商品id',
  `title`           VARCHAR(200) DEFAULT NULL            COMMENT '活动标题',
  `seckill_price`   INT          NOT NULL                COMMENT '秒杀价，单位：分',
  `total_stock`     INT          NOT NULL                COMMENT '总库存',
  `available_stock` INT          NOT NULL                COMMENT '可售库存（消费端扣减）',
  `start_time`      DATETIME     NOT NULL                COMMENT '开始时间',
  `end_time`        DATETIME     NOT NULL                COMMENT '结束时间',
  `status`          TINYINT      NOT NULL DEFAULT 1      COMMENT '状态 0-停用 1-启用',
  `create_time`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `update_time`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_item_id`   (`item_id`),
  KEY `idx_time_window` (`start_time`, `end_time`),
  KEY `idx_status`    (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='秒杀活动表';

DROP TABLE IF EXISTS `seckill_order`;
CREATE TABLE `seckill_order` (
  `id`          BIGINT   NOT NULL                COMMENT '秒杀订单id（雪花算法预生成）',
  `activity_id` BIGINT   NOT NULL                COMMENT '活动id',
  `user_id`     BIGINT   NOT NULL                COMMENT '用户id',
  `item_id`     BIGINT   NOT NULL                COMMENT '商品id',
  `num`         INT      NOT NULL DEFAULT 1      COMMENT '数量',
  `price`       INT      NOT NULL                COMMENT '成交价，单位：分',
  `status`      TINYINT  NOT NULL DEFAULT 0      COMMENT '状态 0-处理中 1-待支付 2-已支付 3-已取消 9-失败',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_activity_user` (`activity_id`, `user_id`),
  KEY `idx_user_id`  (`user_id`),
  KEY `idx_status`   (`status`, `create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='秒杀订单表';

-- -------------------------------------------------------------
-- 测试活动：给商品 3 做一个长期有效的秒杀活动（时间窗口开得很宽，方便随时演示）
-- 秒杀价 990 分（¥9.90），总库存 100
-- -------------------------------------------------------------
INSERT INTO `seckill_activity`
  (`id`, `item_id`, `title`, `seckill_price`, `total_stock`, `available_stock`, `start_time`, `end_time`, `status`)
VALUES
  (1001, 3, '青柠秒杀 · 限量 100 件', 990, 100, 100, '2024-01-01 00:00:00', '2030-12-31 23:59:59', 1);
