package com.product.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record ProductRequest(
    @NotBlank(message = "SKU is required")
    @Size(max = 20, message = "SKU must not exceed 20 characters")
    String sku,

    @NotBlank(message = "Product name is required")
    @Size(max = 200, message = "Product name must not exceed 200 characters")
    String name,

    @Size(max = 500, message = "Description must not exceed 500 characters")
    String description,

    @NotBlank(message = "Category is required")
    @Size(max = 50, message = "Category must not exceed 50 characters")
    String category,

    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than 0")
    BigDecimal price,

    @NotNull(message = "Cost is required")
    @DecimalMin(value = "0.00", message = "Cost must be 0 or greater")
    BigDecimal cost,

    @NotNull(message = "Stock quantity is required")
    @Min(value = 0, message = "Stock quantity must be 0 or greater")
    Integer stockQuantity,

    @NotBlank(message = "Manufacturer is required")
    @Size(max = 100, message = "Manufacturer must not exceed 100 characters")
    String manufacturer,

    @NotBlank(message = "Supplier is required")
    @Size(max = 100, message = "Supplier must not exceed 100 characters")
    String supplier,

    @DecimalMin(value = "0.00", message = "Weight must be 0 or greater")
    BigDecimal weight,

    @Size(max = 30, message = "Dimensions must not exceed 30 characters")
    String dimensions,

    @NotNull(message = "Active status is required")
    Boolean isActive
) {}
