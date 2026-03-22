package com.salesorder.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record OrderDetailRequest(
    @NotBlank(message = "Product ID is required")
    @Size(max = 20, message = "Product ID must not exceed 20 characters")
    String productId,

    @NotBlank(message = "Product name is required")
    @Size(max = 200, message = "Product name must not exceed 200 characters")
    String productName,

    @NotNull(message = "Quantity is required")
    @Min(value = 1, message = "Quantity must be at least 1")
    Integer quantity,

    @NotNull(message = "Unit price is required")
    @DecimalMin(value = "0.01", message = "Unit price must be greater than 0")
    BigDecimal unitPrice,

    @NotNull(message = "Subtotal is required")
    @DecimalMin(value = "0.00", message = "Subtotal must be 0 or greater")
    BigDecimal subtotal
) {}
