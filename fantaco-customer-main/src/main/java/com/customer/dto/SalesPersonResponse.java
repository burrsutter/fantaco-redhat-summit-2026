package com.customer.dto;

import java.time.LocalDateTime;

public record SalesPersonResponse(
    Long id,
    String customerId,
    String firstName,
    String lastName,
    String email,
    String phone,
    String territory,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
