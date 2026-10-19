package com.limemall.cart.config;


import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Data
@Component
@ConfigurationProperties(prefix = "lm.cart")
public class CartProPerties {
    private Integer maxItems;
}
