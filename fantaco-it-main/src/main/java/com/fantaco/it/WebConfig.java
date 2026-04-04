package com.fantaco.it;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        registry.addViewController("/tickets/").setViewName("forward:/tickets/index.html");
        registry.addViewController("/tickets").setViewName("redirect:/tickets/");
    }
}
