package com.product.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record ProductResponse(
    String sku,
    String name,
    String description,
    String category,
    BigDecimal price,
    BigDecimal cost,
    Integer stockQuantity,
    String manufacturer,
    String supplier,
    BigDecimal weight,
    String dimensions,
    Boolean isActive,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
