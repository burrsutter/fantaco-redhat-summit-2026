package com.product.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class CatalogRedirectController {

    @GetMapping({"/catalog", "/catalog/"})
    public String catalog() {
        return "redirect:/catalog/index.html";
    }
}
