package com.customer.dto;

import java.time.LocalDateTime;

public record CustomerContactResponse(
    Long id,
    String customerId,
    String firstName,
    String lastName,
    String email,
    String title,
    String phone,
    String notes,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
