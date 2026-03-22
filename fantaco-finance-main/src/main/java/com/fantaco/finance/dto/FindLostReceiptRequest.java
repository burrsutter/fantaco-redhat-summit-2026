package com.fantaco.finance.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "Request object for finding or regenerating a lost receipt")
public class FindLostReceiptRequest {

    @Schema(description = "Unique identifier for the customer", example = "CUST001", required = true)
    @NotBlank(message = "Customer ID is required")
    private String customerId;

    @Schema(description = "Order number associated with the receipt", example = "ORD-2024-0001", required = true)
    @NotBlank(message = "Order number is required")
    private String orderNumber;

    // Constructors
    public FindLostReceiptRequest() {}

    public FindLostReceiptRequest(String customerId, String orderNumber) {
        this.customerId = customerId;
        this.orderNumber = orderNumber;
    }

    // Getters and Setters
    public String getCustomerId() {
        return customerId;
    }

    public void setCustomerId(String customerId) {
        this.customerId = customerId;
    }

    public String getOrderNumber() {
        return orderNumber;
    }

    public void setOrderNumber(String orderNumber) {
        this.orderNumber = orderNumber;
    }

    @Override
    public String toString() {
        return "FindLostReceiptRequest{" +
                "customerId='" + customerId + '\'' +
                ", orderNumber='" + orderNumber + '\'' +
                '}';
    }
}
