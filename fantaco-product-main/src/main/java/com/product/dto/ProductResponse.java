package com.product.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

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
    List<String> podThemes,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
