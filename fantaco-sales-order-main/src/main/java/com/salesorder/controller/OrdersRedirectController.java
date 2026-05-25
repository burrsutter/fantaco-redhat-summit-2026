package com.salesorder.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class OrdersRedirectController {

    @GetMapping({"/orders", "/orders/"})
    public String orders() {
        return "redirect:/orders/index.html";
    }
}
