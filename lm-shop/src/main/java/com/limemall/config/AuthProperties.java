package com.limemall.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.List;

@Data
@ConfigurationProperties(prefix = "lm.auth")
public class AuthProperties {
    private List<String> includePaths;
    private List<String> excludePaths;
}
