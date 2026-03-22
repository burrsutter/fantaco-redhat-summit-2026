package com.salesorder.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public record SalesOrderResponse(
    String orderNumber,
    String customerId,
    String customerName,
    LocalDateTime orderDate,
    String status,
    BigDecimal totalAmount,
    List<OrderDetailResponse> orderDetails,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
