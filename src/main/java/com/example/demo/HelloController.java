package com.example.demo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    // Reads the setting app.message. Kubernetes can set it with the
    // environment variable APP_MESSAGE. If nothing is set, use the default.
    @Value("${app.message:Hello from Spring Boot}")
    private String message;

    @GetMapping("/hello")
    public String hello() {
        return message;
    }
}
