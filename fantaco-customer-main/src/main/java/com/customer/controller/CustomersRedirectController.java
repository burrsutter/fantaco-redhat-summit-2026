package com.customer.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class CustomersRedirectController {

    @GetMapping({"/customers", "/customers/"})
    public String customers() {
        return "redirect:/customers/index.html";
    }
}
