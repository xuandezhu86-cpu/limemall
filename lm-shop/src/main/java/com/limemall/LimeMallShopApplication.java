package com.limemall;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 单体基线版本的启动类（与微服务版 lm-gateway 同占 8080，不能同时启动）。
 */
@MapperScan("com.limemall.mapper")
@SpringBootApplication
public class LimeMallShopApplication {
    public static void main(String[] args) {
        SpringApplication.run(LimeMallShopApplication.class, args);
    }
}
