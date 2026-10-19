-- =============================================================
-- 青柠商城 limemall · 单体版数据库（lm-shop）
-- 数据库：`lm_shop`
--
-- 依据：lm-shop/src/main/java/com/limemall/domain/po/ 下的全部 PO
--       Item / Cart / Order / OrderDetail / OrderLogistics / User / Address / PayOrder
--       以及 lm-shop/src/main/java/com/limemall/enums/UserStatus.java
--   说明：单体版 PO 与微服务版 PO 字段完全一致（已逐个核对），故表结构与
--         lm_item / lm_cart / lm_trade / lm_user / lm_pay 各库对应表相同。
--
-- 共 8 张表：item、cart、`order`、order_detail、order_logistics、user、address、pay_order
-- 测试数据：item 24 条、user 2 条、address 4 条、cart 3 条；
--           order / order_detail / order_logistics / pay_order 为空表
-- 枚举列：`user`.`status` = 0 (FROZEN 禁止使用) / 1 (NORMAL 已激活)
-- 约定：所有金额字段（price、total_fee、balance、amount）均为 Integer，单位「分」
--       User PO 无 info 字段，故不建 info 列
--       时间列：DATETIME；create_time 默认 CURRENT_TIMESTAMP，update_time 默认
--       CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP（Java 代码中未设置时间字段，
--       也没有 MetaObjectHandler）；种子数据仍全部写固定字面量，便于复现。
-- =============================================================

SET NAMES utf8mb4;

USE `lm_shop`;

-- -------------------------------------------------------------
-- 1. 商品表
-- -------------------------------------------------------------
DROP TABLE IF EXISTS `item`;
CREATE TABLE `item` (
  `id`            BIGINT       NOT NULL AUTO_INCREMENT           COMMENT '商品id',
  `name`          VARCHAR(200) DEFAULT NULL                          COMMENT 'SKU名称',
  `price`         INT          NOT NULL DEFAULT 0                COMMENT '价格（分）',
  `stock`         INT          NOT NULL DEFAULT 0                COMMENT '库存数量',
  `image`         VARCHAR(500) DEFAULT NULL                      COMMENT '商品图片URL',
  `category`      VARCHAR(100) DEFAULT NULL                      COMMENT '类目名称',
  `brand`         VARCHAR(100) DEFAULT NULL                      COMMENT '品牌名称',
  `spec`          VARCHAR(500) DEFAULT NULL                      COMMENT '规格（JSON字符串）',
  `sold`          INT          NOT NULL DEFAULT 0                COMMENT '销量',
  `comment_count` INT          NOT NULL DEFAULT 0                COMMENT '评论数',
  `isAD`          TINYINT(1)   NOT NULL DEFAULT 0                COMMENT '是否是推广广告 0-否 1-是',
  `status`        TINYINT      NOT NULL DEFAULT 1                COMMENT '商品状态 1-正常 2-下架 3-删除',
  `create_time`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `creater`       BIGINT       DEFAULT NULL                      COMMENT '创建人',
  `updater`       BIGINT       DEFAULT NULL                      COMMENT '修改人',
  PRIMARY KEY (`id`),
  KEY `idx_category`    (`category`),
  KEY `idx_brand`       (`brand`),
  KEY `idx_status`      (`status`),
  KEY `idx_price`       (`price`),
  KEY `idx_update_time` (`update_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品表';

-- -------------------------------------------------------------
-- 2. 购物车表
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- 3. 订单表（表名是 MySQL 关键字，必须反引号）
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- 4. 订单详情表
-- -------------------------------------------------------------
DROP TABLE IF EXISTS `order_detail`;
CREATE TABLE `order_detail` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '订单详情id',
  `order_id`    BIGINT       NOT NULL                COMMENT '订单id',
  `item_id`     BIGINT       NOT NULL                COMMENT 'sku商品id',
  `num`         INT          NOT NULL DEFAULT 1      COMMENT '购买数量',
  `name`        VARCHAR(200) DEFAULT NULL                COMMENT '商品标题',
  `spec`        VARCHAR(500) DEFAULT NULL            COMMENT '商品动态属性键值集（JSON字符串）',
  `price`       INT          NOT NULL DEFAULT 0      COMMENT '价格，单位：分',
  `image`       VARCHAR(500) DEFAULT NULL            COMMENT '商品图片',
  `create_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_order_id` (`order_id`),
  KEY `idx_item_id`  (`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单详情表';

-- -------------------------------------------------------------
-- 5. 订单物流表（主键是 order_id，与订单表一对一）
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- 6. 用户表（status 存 UserStatus 的 @EnumValue：0-FROZEN，1-NORMAL）
-- -------------------------------------------------------------
DROP TABLE IF EXISTS `user`;
CREATE TABLE `user` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '用户id',
  `username`    VARCHAR(50)  NOT NULL                COMMENT '用户名',
  `password`    VARCHAR(128) NOT NULL                COMMENT '密码，BCrypt 加密存储',
  `phone`       VARCHAR(20)  DEFAULT NULL            COMMENT '注册手机号',
  `create_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `status`      TINYINT      NOT NULL DEFAULT 1      COMMENT '使用状态 0-FROZEN禁止使用 1-NORMAL已激活',
  `balance`     INT          NOT NULL DEFAULT 0      COMMENT '账户余额，单位：分',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username` (`username`),
  KEY `idx_phone`  (`phone`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户表';

-- -------------------------------------------------------------
-- 7. 收货地址表
-- -------------------------------------------------------------
DROP TABLE IF EXISTS `address`;
CREATE TABLE `address` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '地址id',
  `user_id`    BIGINT       NOT NULL                COMMENT '用户ID',
  `province`   VARCHAR(50)  DEFAULT NULL            COMMENT '省',
  `city`       VARCHAR(50)  DEFAULT NULL            COMMENT '市',
  `town`       VARCHAR(50)  DEFAULT NULL            COMMENT '县/区',
  `mobile`     VARCHAR(20)  DEFAULT NULL            COMMENT '手机',
  `street`     VARCHAR(255) DEFAULT NULL            COMMENT '详细地址',
  `contact`    VARCHAR(50)  DEFAULT NULL            COMMENT '联系人',
  `is_default` TINYINT(1)   NOT NULL DEFAULT 0      COMMENT '是否是默认 1-默认 0-否',
  `notes`      VARCHAR(255) DEFAULT NULL            COMMENT '备注',
  PRIMARY KEY (`id`),
  KEY `idx_user_id`      (`user_id`),
  KEY `idx_user_default` (`user_id`, `is_default`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='收货地址表';

-- -------------------------------------------------------------
-- 8. 支付订单表
-- -------------------------------------------------------------
DROP TABLE IF EXISTS `pay_order`;
CREATE TABLE `pay_order` (
  `id`               BIGINT        NOT NULL                COMMENT '支付单id（雪花算法生成，非自增）',
  `biz_order_no`     BIGINT        NOT NULL                COMMENT '业务订单号（order.id）',
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

-- =============================================================
-- 测试数据（与各微服务库保持同一批值）
-- =============================================================

-- 商品 24 条：价格 ¥9.90 ~ ¥9999.00（price 单位分），
-- 广告位 isAD=1：id 1、7、13、19、24；下架 status=2：id 5、11、17、23
INSERT INTO `item` (`id`, `name`, `price`, `stock`, `image`, `category`, `brand`, `spec`, `sold`, `comment_count`, `isAD`, `status`, `create_time`, `update_time`, `creater`, `updater`) VALUES
(1,  '绿联 Type-C 数据线 1.5米 快充线',              990,   5000, 'https://picsum.photos/seed/lm1/300/300',  '手机配件',   '绿联',     '{"颜色": "白色", "长度": "1.5米"}',       52800, 12034, 1, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(2,  '小米 移动电源 10000mAh 22.5W快充',             1990,  3000, 'https://picsum.photos/seed/lm2/300/300',  '手机配件',   '小米',     '{"颜色": "黑色", "容量": "10000mAh"}',    31200, 5210,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(3,  '华为 原装 66W 超级快充充电器',                 2990,  2000, 'https://picsum.photos/seed/lm3/300/300',  '手机配件',   '华为',     '{"颜色": "白色", "功率": "66W"}',         18800, 3402,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(4,  '罗技 M185 无线鼠标 黑色',                      4990,  1200, 'https://picsum.photos/seed/lm4/300/300',  '电脑外设',   '罗技',     '{"颜色": "黑色", "连接方式": "2.4G无线"}', 9800,  2101,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(5,  '绿联 HiTune T3 主动降噪蓝牙耳机',              6900,  800,  'https://picsum.photos/seed/lm5/300/300',  '耳机',       '绿联',     '{"颜色": "白色"}',                        7600,  1200,  0, 2, '2024-04-10 09:15:00', '2024-06-01 10:00:00', 1, 1),
(6,  '漫步者 W200BT 颈挂式蓝牙耳机',                 9900,  900,  'https://picsum.photos/seed/lm6/300/300',  '耳机',       '漫步者',   '{"颜色": "黑色"}',                        15000, 4210,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(7,  '小米 Redmi Buds 4 活力版 真无线耳机',          12900, 700,  'https://picsum.photos/seed/lm7/300/300',  '耳机',       '小米',     '{"颜色": "白色"}',                        23000, 5100,  1, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(8,  '安踏 男士缓震跑步鞋',                          15900, 600,  'https://picsum.photos/seed/lm8/300/300',  '运动鞋',     '安踏',     '{"颜色": "黑色", "尺码": "42"}',          12000, 3300,  0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(9,  '李宁 男士篮球鞋 音速11',                       19900, 450,  'https://picsum.photos/seed/lm9/300/300',  '运动鞋',     '李宁',     '{"颜色": "蓝色", "尺码": "43"}',           8600,  1900,  0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(10, '卡西欧 男士石英手表 MTP-1375D',                29900, 300,  'https://picsum.photos/seed/lm10/300/300', '手表',       '卡西欧',   '{"表盘": "银色", "表带": "钢带"}',         4200,  980,   0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(11, '花花公子 男士真皮单肩包 商务款',               39900, 200,  'https://picsum.photos/seed/lm11/300/300', '真皮包',     '花花公子', '{"颜色": "黑色"}',                        3600,  760,   0, 2, '2024-04-18 14:20:00', '2024-06-01 10:00:00', 1, 1),
(12, '莎米特 拉杆箱 22英寸 PC万向轮',                49900, 260,  'https://picsum.photos/seed/lm12/300/300', '拉杆箱',     '莎米特',   '{"颜色": "红色", "尺寸": "22英寸"}',       5400,  1100,  0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(13, '米家 空气净化器 4',                            59900, 180,  'https://picsum.photos/seed/lm13/300/300', '空气净化器', '小米',     '{"适用面积": "60平方米"}',                 6800,  1500,  1, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(14, '美的 智能电饭煲 4L',                           79900, 160,  'https://picsum.photos/seed/lm14/300/300', '电饭煲',     '美的',     '{"容量": "4L"}',                          5200,  1300,  0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(15, '格兰仕 微波炉 23L 家用',                       99900, 140,  'https://picsum.photos/seed/lm15/300/300', '微波炉',     '格兰仕',   '{"容量": "23L"}',                         3100,  820,   0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(16, 'AOC 27英寸 2K 显示器 Q27G2S',                  129900,120,  'https://picsum.photos/seed/lm16/300/300', '显示器',     'AOC',      '{"尺寸": "27英寸", "分辨率": "2K"}',       2600,  640,   0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(17, '海尔 10kg 滚筒洗衣机 洗烘一体',                199900,90,   'https://picsum.photos/seed/lm17/300/300', '洗衣机',     '海尔',     '{"容量": "10kg"}',                        1800,  430,   0, 2, '2024-04-25 11:05:00', '2024-06-01 10:00:00', 1, 1),
(18, '海尔 501L 十字对开门冰箱',                     259900,80,   'https://picsum.photos/seed/lm18/300/300', '冰箱',       '海尔',     '{"容量": "501L"}',                        1500,  380,   0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(19, 'TCL 65英寸 4K 液晶电视 65T8E',                 359900,70,   'https://picsum.photos/seed/lm19/300/300', '电视',       'TCL',      '{"尺寸": "65英寸"}',                      2200,  510,   1, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(20, '格力 1.5匹 变频冷暖挂机空调',                  499900,60,   'https://picsum.photos/seed/lm20/300/300', '空调',       '格力',     '{"匹数": "1.5匹"}',                       1200,  300,   0, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(21, '联想 小新Pro16 轻薄笔记本 i5/16GB/1TB',        599900,50,   'https://picsum.photos/seed/lm21/300/300', '笔记本',     '联想',     '{"配置": "i5/16GB/1TB"}',                 900,   210,   0, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(22, 'vivo X100 12GB+256GB 星迹蓝',                  699900,45,   'https://picsum.photos/seed/lm22/300/300', '手机',       'vivo',     '{"颜色": "星迹蓝", "存储": "12GB+256GB"}', 1600,  480,   0, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(23, '华为 MateBook X Pro 2024 i7/16GB/1TB',         899900,30,   'https://picsum.photos/seed/lm23/300/300', '笔记本',     '华为',     '{"配置": "i7/16GB/1TB"}',                 600,   150,   0, 2, '2024-05-06 16:40:00', '2024-06-01 10:00:00', 1, 1),
(24, '三星 85英寸 8K 量子点电视 QA85QN900C',         999900,10,   'https://picsum.photos/seed/lm24/300/300', '电视',       '三星',     '{"尺寸": "85英寸"}',                      120,   36,    1, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1);

-- 用户 2 条（password 为占位符，后续替换真实 BCrypt 哈希）
INSERT INTO `user` (`id`, `username`, `password`, `phone`, `create_time`, `update_time`, `status`, `balance`) VALUES
(1, 'jack', '$2a$10$50jqkcFiaAt42HC1i4INV.GX5tQWx8GHQwaSIREKbbXLwluHgaCyC', '13800138001', '2024-05-01 10:00:00', '2024-05-01 10:00:00', 1, 1000000),
(2, 'Rose', '$2a$10$50jqkcFiaAt42HC1i4INV.GX5tQWx8GHQwaSIREKbbXLwluHgaCyC', '13800138002', '2024-05-01 10:00:00', '2024-05-01 10:00:00', 1, 500000);

-- 地址 4 条（每个用户 2 条，各含 1 条默认地址）
INSERT INTO `address` (`id`, `user_id`, `province`, `city`, `town`, `mobile`, `street`, `contact`, `is_default`, `notes`) VALUES
(1, 1, '广东省', '深圳市', '南山区', '13800138001', '科技园南区 8 栋 501 室', '杰克', 1, '公司地址'),
(2, 1, '广东省', '广州市', '天河区', '13900139001', '天河路 385 号 1203 室', '杰克', 0, '家里'),
(3, 2, '上海市', '上海市', '浦东新区', '13800138002', '张江高科技园区 88 号 2 栋 902 室', '罗斯', 1, '家'),
(4, 2, '浙江省', '杭州市', '西湖区', '13900139002', '文三路 90 号 5 幢 301 室', '罗斯', 0, '父母家');

-- 购物车 3 条（引用上面的商品，标题/规格/价格与 item 表一致）
INSERT INTO `cart` (`id`, `user_id`, `item_id`, `num`, `name`, `spec`, `price`, `image`, `create_time`, `update_time`) VALUES
(1, 1, 1,  2, '绿联 Type-C 数据线 1.5米 快充线',      '{"颜色": "白色", "长度": "1.5米"}',       990,   'https://picsum.photos/seed/lm1/300/300',  '2024-05-21 09:00:00', '2024-05-21 09:00:00'),
(2, 1, 7,  1, '小米 Redmi Buds 4 活力版 真无线耳机',   '{"颜色": "白色"}',                        12900, 'https://picsum.photos/seed/lm7/300/300',  '2024-05-21 09:05:00', '2024-05-21 09:05:00'),
(3, 2, 12, 1, '莎米特 拉杆箱 22英寸 PC万向轮',         '{"颜色": "红色", "尺寸": "22英寸"}',      49900, 'https://picsum.photos/seed/lm12/300/300', '2024-05-22 20:10:00', '2024-05-22 20:10:00');

-- order / order_detail / order_logistics / pay_order 为空表，不插入数据
