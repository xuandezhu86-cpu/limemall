-- =============================================================
-- 青柠商城 limemall（Spring Cloud Alibaba 版）· 商品库
-- 数据库：`lm_item`    微服务：item-service
--
-- 依据：item-service/src/main/java/com/limemall/item/domain/po/Item.java
--       （@TableName("item")、@TableId(value="id", type=AUTO)、
--         @TableField("isAD") 显式指定列名）
--       item-service/src/main/java/com/limemall/item/mapper/ItemMapper.java
--       （updateStock：UPDATE item SET stock = stock - #{num} WHERE id = #{itemId}）
--
-- 约定：MyBatis-Plus 3.4.2 默认驼峰转下划线，Java 字段 -> 列名
--       price 为 Integer，单位「分」：¥9.90 => 990，¥9999.00 => 999900
--       isAD 为 Boolean，用 TINYINT(1) 存 0/1
--       status：1-正常 2-下架 3-删除（Integer，非枚举）
--       时间列：DATETIME；create_time 默认 CURRENT_TIMESTAMP，update_time 默认
--       CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP（Java 代码中未设置时间字段，
--       也没有 MetaObjectHandler）；种子数据仍全部写固定字面量，便于复现。
-- =============================================================

SET NAMES utf8mb4;

USE `lm_item`;

DROP TABLE IF EXISTS `item`;
CREATE TABLE `item` (
  `id`            BIGINT       NOT NULL AUTO_INCREMENT           COMMENT '商品id',
  `name`          VARCHAR(200) NOT NULL                          COMMENT 'SKU名称',
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
-- 测试数据：24 条商品
--   * 价格覆盖 ¥9.90 ~ ¥9999.00（price 以「分」存储：990 ~ 999900）
--   * 广告位 isAD = 1：id 1、7、13、19、24（共 5 条）
--   * 下架状态 status = 2：id 5、11、17、23（共 4 条）
--   * 时间均为固定字面量，便于复现
-- -------------------------------------------------------------
INSERT INTO `item` (`id`, `name`, `price`, `stock`, `image`, `category`, `brand`, `spec`, `sold`, `comment_count`, `isAD`, `status`, `create_time`, `update_time`, `creater`, `updater`) VALUES
(1,  '绿联 Type-C 数据线 1.5米 快充线',              990,   5000, 'https://picsum.photos/seed/hm1/300/300',  '手机配件',   '绿联',     '{"颜色": "白色", "长度": "1.5米"}',       52800, 12034, 1, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(2,  '小米 移动电源 10000mAh 22.5W快充',             1990,  3000, 'https://picsum.photos/seed/hm2/300/300',  '手机配件',   '小米',     '{"颜色": "黑色", "容量": "10000mAh"}',    31200, 5210,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(3,  '华为 原装 66W 超级快充充电器',                 2990,  2000, 'https://picsum.photos/seed/hm3/300/300',  '手机配件',   '华为',     '{"颜色": "白色", "功率": "66W"}',         18800, 3402,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(4,  '罗技 M185 无线鼠标 黑色',                      4990,  1200, 'https://picsum.photos/seed/hm4/300/300',  '电脑外设',   '罗技',     '{"颜色": "黑色", "连接方式": "2.4G无线"}', 9800,  2101,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(5,  '绿联 HiTune T3 主动降噪蓝牙耳机',              6900,  800,  'https://picsum.photos/seed/hm5/300/300',  '耳机',       '绿联',     '{"颜色": "白色"}',                        7600,  1200,  0, 2, '2024-04-10 09:15:00', '2024-06-01 10:00:00', 1, 1),
(6,  '漫步者 W200BT 颈挂式蓝牙耳机',                 9900,  900,  'https://picsum.photos/seed/hm6/300/300',  '耳机',       '漫步者',   '{"颜色": "黑色"}',                        15000, 4210,  0, 1, '2024-04-10 09:15:00', '2024-05-20 18:30:00', 1, 1),
(7,  '小米 Redmi Buds 4 活力版 真无线耳机',          12900, 700,  'https://picsum.photos/seed/hm7/300/300',  '耳机',       '小米',     '{"颜色": "白色"}',                        23000, 5100,  1, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(8,  '安踏 男士缓震跑步鞋',                          15900, 600,  'https://picsum.photos/seed/hm8/300/300',  '运动鞋',     '安踏',     '{"颜色": "黑色", "尺码": "42"}',          12000, 3300,  0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(9,  '李宁 男士篮球鞋 音速11',                       19900, 450,  'https://picsum.photos/seed/hm9/300/300',  '运动鞋',     '李宁',     '{"颜色": "蓝色", "尺码": "43"}',           8600,  1900,  0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(10, '卡西欧 男士石英手表 MTP-1375D',                29900, 300,  'https://picsum.photos/seed/hm10/300/300', '手表',       '卡西欧',   '{"表盘": "银色", "表带": "钢带"}',         4200,  980,   0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(11, '花花公子 男士真皮单肩包 商务款',               39900, 200,  'https://picsum.photos/seed/hm11/300/300', '真皮包',     '花花公子', '{"颜色": "黑色"}',                        3600,  760,   0, 2, '2024-04-18 14:20:00', '2024-06-01 10:00:00', 1, 1),
(12, '莎米特 拉杆箱 22英寸 PC万向轮',                49900, 260,  'https://picsum.photos/seed/hm12/300/300', '拉杆箱',     '莎米特',   '{"颜色": "红色", "尺寸": "22英寸"}',       5400,  1100,  0, 1, '2024-04-18 14:20:00', '2024-05-20 18:30:00', 1, 1),
(13, '米家 空气净化器 4',                            59900, 180,  'https://picsum.photos/seed/hm13/300/300', '空气净化器', '小米',     '{"适用面积": "60平方米"}',                 6800,  1500,  1, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(14, '美的 智能电饭煲 4L',                           79900, 160,  'https://picsum.photos/seed/hm14/300/300', '电饭煲',     '美的',     '{"容量": "4L"}',                          5200,  1300,  0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(15, '格兰仕 微波炉 23L 家用',                       99900, 140,  'https://picsum.photos/seed/hm15/300/300', '微波炉',     '格兰仕',   '{"容量": "23L"}',                         3100,  820,   0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(16, 'AOC 27英寸 2K 显示器 Q27G2S',                  129900,120,  'https://picsum.photos/seed/hm16/300/300', '显示器',     'AOC',      '{"尺寸": "27英寸", "分辨率": "2K"}',       2600,  640,   0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(17, '海尔 10kg 滚筒洗衣机 洗烘一体',                199900,90,   'https://picsum.photos/seed/hm17/300/300', '洗衣机',     '海尔',     '{"容量": "10kg"}',                        1800,  430,   0, 2, '2024-04-25 11:05:00', '2024-06-01 10:00:00', 1, 1),
(18, '海尔 501L 十字对开门冰箱',                     259900,80,   'https://picsum.photos/seed/hm18/300/300', '冰箱',       '海尔',     '{"容量": "501L"}',                        1500,  380,   0, 1, '2024-04-25 11:05:00', '2024-05-20 18:30:00', 1, 1),
(19, 'TCL 65英寸 4K 液晶电视 65T8E',                 359900,70,   'https://picsum.photos/seed/hm19/300/300', '电视',       'TCL',      '{"尺寸": "65英寸"}',                      2200,  510,   1, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(20, '格力 1.5匹 变频冷暖挂机空调',                  499900,60,   'https://picsum.photos/seed/hm20/300/300', '空调',       '格力',     '{"匹数": "1.5匹"}',                       1200,  300,   0, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(21, '联想 小新Pro16 轻薄笔记本 i5/16GB/1TB',        599900,50,   'https://picsum.photos/seed/hm21/300/300', '笔记本',     '联想',     '{"配置": "i5/16GB/1TB"}',                 900,   210,   0, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(22, 'vivo X100 12GB+256GB 星迹蓝',                  699900,45,   'https://picsum.photos/seed/hm22/300/300', '手机',       'vivo',     '{"颜色": "星迹蓝", "存储": "12GB+256GB"}', 1600,  480,   0, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1),
(23, '华为 MateBook X Pro 2024 i7/16GB/1TB',         899900,30,   'https://picsum.photos/seed/hm23/300/300', '笔记本',     '华为',     '{"配置": "i7/16GB/1TB"}',                 600,   150,   0, 2, '2024-05-06 16:40:00', '2024-06-01 10:00:00', 1, 1),
(24, '三星 85英寸 8K 量子点电视 QA85QN900C',         999900,10,   'https://picsum.photos/seed/hm24/300/300', '电视',       '三星',     '{"尺寸": "85英寸"}',                      120,   36,    1, 1, '2024-05-06 16:40:00', '2024-05-20 18:30:00', 1, 1);
