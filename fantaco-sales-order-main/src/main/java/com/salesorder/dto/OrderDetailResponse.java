package com.salesorder.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record OrderDetailResponse(
    Long id,
    String productId,
    String productName,
    Integer quantity,
    BigDecimal unitPrice,
    BigDecimal subtotal,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
