-- =============================================================
-- 青柠商城 limemall（Spring Cloud Alibaba 版）· 用户库
-- 数据库：`lm_user`    微服务：user-service
--
-- 依据：user-service/src/main/java/com/limemall/user/domain/po/User.java
--       user-service/src/main/java/com/limemall/user/domain/po/Address.java
--       user-service/src/main/java/com/limemall/user/enums/UserStatus.java
--       user-service/src/main/java/com/limemall/user/mapper/UserMapper.java
--       （updateMoney：update user set balance = balance - ${totalFee} where id = #{userId}）
--       user-service/src/main/java/com/limemall/user/controller/AddressController.java
--       （address 按 user_id 查询）
--
-- 枚举列（重点）：
--   UserStatus 使用 @EnumValue 标注 int value，所以 `user`.`status` 存的是整数：
--       0 = FROZEN  禁止使用
--       1 = NORMAL  已激活
--   （注意：User PO 的 Javadoc 写的是「1正常 2冻结」，与枚举类实际取值不一致，
--     以枚举类 UserStatus 为准。业务代码 UserServiceImpl 用
--     user.getStatus() == UserStatus.FROZEN 判断冻结，即 0 为冻结。）
--
-- 说明：User PO 中没有 info 字段（字段仅 id/username/password/phone/
--       createTime/updateTime/status/balance），故本表不建 info 列。
--       balance 为 Integer，单位「分」：1000000 => ¥10000.00。
--       时间列：DATETIME；create_time 默认 CURRENT_TIMESTAMP，update_time 默认
--       CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP（Java 代码中未设置时间字段，
--       也没有 MetaObjectHandler）；种子数据仍全部写固定字面量，便于复现。
-- =============================================================

SET NAMES utf8mb4;

USE `lm_user`;

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
-- 测试数据
--   * 用户 2 条：jack、Rose（status=1 已激活；balance 单位分）
--   * password 为占位符 $2a$10$50jqkcFiaAt42HC1i4INV.GX5tQWx8GHQwaSIREKbbXLwluHgaCyC，后续替换为真实 BCrypt 哈希
--   * address 4 条：每个用户 2 条，各自 1 条默认地址（is_default=1）
--   * 时间均为固定字面量
-- -------------------------------------------------------------
INSERT INTO `user` (`id`, `username`, `password`, `phone`, `create_time`, `update_time`, `status`, `balance`) VALUES
(1, 'jack', '$2a$10$50jqkcFiaAt42HC1i4INV.GX5tQWx8GHQwaSIREKbbXLwluHgaCyC', '13800138001', '2024-05-01 10:00:00', '2024-05-01 10:00:00', 1, 1000000),
(2, 'Rose', '$2a$10$50jqkcFiaAt42HC1i4INV.GX5tQWx8GHQwaSIREKbbXLwluHgaCyC', '13800138002', '2024-05-01 10:00:00', '2024-05-01 10:00:00', 1, 500000);

INSERT INTO `address` (`id`, `user_id`, `province`, `city`, `town`, `mobile`, `street`, `contact`, `is_default`, `notes`) VALUES
(1, 1, '广东省', '深圳市', '南山区', '13800138001', '科技园南区 8 栋 501 室', '杰克', 1, '公司地址'),
(2, 1, '广东省', '广州市', '天河区', '13900139001', '天河路 385 号 1203 室', '杰克', 0, '家里'),
(3, 2, '上海市', '上海市', '浦东新区', '13800138002', '张江高科技园区 88 号 2 栋 902 室', '罗斯', 1, '家'),
(4, 2, '浙江省', '杭州市', '西湖区', '13900139002', '文三路 90 号 5 幢 301 室', '罗斯', 0, '父母家');
