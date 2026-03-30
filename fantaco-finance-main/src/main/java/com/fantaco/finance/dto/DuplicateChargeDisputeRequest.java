package com.fantaco.finance.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "Request object for starting a duplicate charge dispute")
public class DuplicateChargeDisputeRequest {

    @Schema(description = "Unique identifier for the customer", example = "CUST001", required = true)
    @NotBlank(message = "Customer ID is required")
    private String customerId;

    @Schema(description = "Order number associated with the dispute", example = "ORD-2025-0001", required = true)
    @NotBlank(message = "Order number is required")
    private String orderNumber;

    @Schema(description = "Detailed description of the duplicate charge issue", example = "I was charged twice for the same order on 2024-01-15", required = true)
    @NotBlank(message = "Description is required")
    private String description;

    @Schema(description = "Optional reason code for the dispute", example = "DUPLICATE_PAYMENT")
    private String reason;

    // Constructors
    public DuplicateChargeDisputeRequest() {}

    public DuplicateChargeDisputeRequest(String customerId, String orderNumber, String description) {
        this.customerId = customerId;
        this.orderNumber = orderNumber;
        this.description = description;
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

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getReason() {
        return reason;
    }

    public void setReason(String reason) {
        this.reason = reason;
    }

    @Override
    public String toString() {
        return "DuplicateChargeDisputeRequest{" +
                "customerId='" + customerId + '\'' +
                ", orderNumber='" + orderNumber + '\'' +
                ", description='" + description + '\'' +
                ", reason='" + reason + '\'' +
                '}';
    }
}
