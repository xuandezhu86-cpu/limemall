-- =============================================================
-- 青柠商城 limemall（Spring Cloud Alibaba 版）· 00 建库脚本
-- MySQL 8.0 / InnoDB / utf8mb4
--
-- 说明：
--   1. 本脚本只创建 6 个空库，不建表、不插数据；
--   2. 各库的表结构与测试数据见同目录下的 lm_item.sql、lm_cart.sql、
--      lm_trade.sql、lm_user.sql、lm_pay.sql、limemall.sql；
--   3. 库名带连字符（lm_item 等），所有库名必须用反引号包裹。
-- =============================================================

SET NAMES utf8mb4;

-- 商品服务 item-service
CREATE DATABASE IF NOT EXISTS `lm_item` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 购物车服务 cart-service
CREATE DATABASE IF NOT EXISTS `lm_cart` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 交易服务 trade-service
CREATE DATABASE IF NOT EXISTS `lm_trade` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 用户服务 user-service
CREATE DATABASE IF NOT EXISTS `lm_user` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 支付服务 pay-service
CREATE DATABASE IF NOT EXISTS `lm_pay` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 单体版 lm-shop
CREATE DATABASE IF NOT EXISTS `lm_shop` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
