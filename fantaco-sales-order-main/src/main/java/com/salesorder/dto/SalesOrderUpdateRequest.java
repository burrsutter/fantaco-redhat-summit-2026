package com.salesorder.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public record SalesOrderUpdateRequest(
    @NotBlank(message = "Customer ID is required")
    @Size(max = 10, message = "Customer ID must not exceed 10 characters")
    String customerId,

    @NotBlank(message = "Customer name is required")
    @Size(max = 100, message = "Customer name must not exceed 100 characters")
    String customerName,

    @NotNull(message = "Order date is required")
    LocalDateTime orderDate,

    @NotBlank(message = "Status is required")
    @Size(max = 20, message = "Status must not exceed 20 characters")
    String status,

    @NotNull(message = "Total amount is required")
    @DecimalMin(value = "0.00", message = "Total amount must be 0 or greater")
    BigDecimal totalAmount,

    @Valid
    List<OrderDetailRequest> orderDetails
) {}
