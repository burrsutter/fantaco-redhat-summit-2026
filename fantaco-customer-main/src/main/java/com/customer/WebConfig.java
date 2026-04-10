package com.customer;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {
    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        registry.addViewController("/customers/")
                .setViewName("forward:/customers/index.html");
        registry.addViewController("/customers")
                .setViewName("forward:/customers/index.html");
    }
}
