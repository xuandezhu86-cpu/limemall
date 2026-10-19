-- =============================================================
-- 青柠商城 limemall（Spring Cloud Alibaba 版）· 购物车库
-- 数据库：`lm_cart`    微服务：cart-service
--
-- 依据：cart-service/src/main/java/com/limemall/cart/domain/po/Cart.java
--       （@TableName("cart")、@TableId(value="id", type=AUTO)）
--       cart-service/src/main/java/com/limemall/cart/mapper/CartMapper.java
--       （updateNum：UPDATE cart SET num = num + 1
--                    WHERE user_id = #{userId} AND item_id = #{itemId}
--         -> 需要 (user_id, item_id) 组合索引）
--       cart-service/src/main/java/com/limemall/cart/service/impl/CartServiceImpl.java
--       （按 user_id 查询、按 user_id + item_id 更新/删除）
--
-- 约定：price 为 Integer，单位「分」；spec 为 JSON 字符串，PO 类型是 String，故用 VARCHAR
--       本库暂无测试数据（按需求不造无意义数据）
--       时间列：DATETIME；create_time 默认 CURRENT_TIMESTAMP，update_time 默认
--       CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP（Java 代码中未设置时间字段，
--       也没有 MetaObjectHandler）；种子数据仍全部写固定字面量，便于复现。
-- =============================================================

SET NAMES utf8mb4;

USE `lm_cart`;

DROP TABLE IF EXISTS `cart`;
CREATE TABLE `cart` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '购物车条目id',
  `user_id`     BIGINT       NOT NULL                COMMENT '用户id',
  `item_id`     BIGINT       NOT NULL                COMMENT 'sku商品id',
  `num`         INT          NOT NULL DEFAULT 1      COMMENT '购买数量',
  `name`        VARCHAR(200) DEFAULT NULL                COMMENT '商品标题',
  `spec`        VARCHAR(500) DEFAULT NULL            COMMENT '商品动态属性键值集（JSON字符串）',
  `price`       INT          NOT NULL DEFAULT 0      COMMENT '价格，单位：分',
  `image`       VARCHAR(500) DEFAULT NULL            COMMENT '商品图片',
  `create_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_user_id`   (`user_id`),
  KEY `idx_user_item` (`user_id`, `item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='购物车表';
