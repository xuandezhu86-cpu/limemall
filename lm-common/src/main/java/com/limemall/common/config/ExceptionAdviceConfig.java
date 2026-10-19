package com.limemall.common.config;

import com.limemall.common.advice.CommonExceptionAdvice;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

/**
 * 统一异常处理的自动装配。
 *
 * <p>只在 Servlet（Spring MVC）应用里生效：{@link CommonExceptionAdvice} 处理了
 * spring-webmvc 的 {@code NestedServletException}，而网关是 WebFlux 应用，
 * classpath 上没有 javax.servlet，直接注册会导致网关启动报
 * {@code NoClassDefFoundError: javax/servlet/ServletException}。</p>
 *
 * @author LimeMall
 */
@Configuration(proxyBeanMethods = false)
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
@Import(CommonExceptionAdvice.class)
public class ExceptionAdviceConfig {
}
