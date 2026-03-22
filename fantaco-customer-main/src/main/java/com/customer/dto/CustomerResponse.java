package com.customer.dto;

import java.time.LocalDateTime;

public record CustomerResponse(
    String customerId,
    String companyName,
    String contactName,
    String contactTitle,
    String address,
    String city,
    String region,
    String postalCode,
    String country,
    String phone,
    String fax,
    String contactEmail,
    String website,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
