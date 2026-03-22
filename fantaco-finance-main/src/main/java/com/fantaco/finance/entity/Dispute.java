package com.fantaco.finance.entity;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import java.time.LocalDateTime;

@Entity
@Table(name = "disputes")
@Schema(description = "Dispute entity representing a customer dispute")
public class Dispute {
    
    @Schema(description = "Unique identifier for the dispute", example = "1")
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Schema(description = "Unique dispute number", example = "DISP-2024-001")
    @NotBlank
    @Column(name = "dispute_number", unique = true, nullable = false)
    private String disputeNumber;
    
    @Schema(description = "Associated order number", example = "ORD-2024-0001")
    @NotBlank
    @Column(name = "order_number", nullable = false)
    private String orderNumber;
    
    @Schema(description = "Customer identifier", example = "CUST-12345")
    @NotBlank
    @Column(name = "customer_id", nullable = false)
    private String customerId;
    
    @Schema(description = "Type of dispute", example = "DUPLICATE_CHARGE")
    @Enumerated(EnumType.STRING)
    @Column(name = "dispute_type", nullable = false)
    private DisputeType disputeType;
    
    @Schema(description = "Current status of the dispute", example = "OPEN")
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private DisputeStatus status;
    
    @Schema(description = "Detailed description of the dispute", example = "I was charged twice for the same order")
    @Column(name = "description", columnDefinition = "TEXT")
    private String description;
    
    @Schema(description = "Reason for the dispute", example = "DUPLICATE_PAYMENT")
    @Column(name = "reason", columnDefinition = "TEXT")
    private String reason;
    
    @Schema(description = "Date when the dispute was created", example = "2024-01-15T10:30:00")
    @Column(name = "dispute_date", nullable = false)
    private LocalDateTime disputeDate;
    
    @Schema(description = "Date when the dispute was resolved", example = "2024-01-20T14:30:00")
    @Column(name = "resolved_date")
    private LocalDateTime resolvedDate;
    
    @Schema(description = "Timestamp when the record was created", example = "2024-01-15T10:30:00")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
    
    @Schema(description = "Timestamp when the record was last updated", example = "2024-01-15T11:00:00")
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
    
    // Constructors
    public Dispute() {
        this.createdAt = LocalDateTime.now();
    }
    
    public Dispute(String disputeNumber, String orderNumber, String customerId, DisputeType disputeType, DisputeStatus status) {
        this();
        this.disputeNumber = disputeNumber;
        this.orderNumber = orderNumber;
        this.customerId = customerId;
        this.disputeType = disputeType;
        this.status = status;
        this.disputeDate = LocalDateTime.now();
    }
    
    // Getters and Setters
    public Long getId() {
        return id;
    }
    
    public void setId(Long id) {
        this.id = id;
    }
    
    public String getDisputeNumber() {
        return disputeNumber;
    }
    
    public void setDisputeNumber(String disputeNumber) {
        this.disputeNumber = disputeNumber;
    }
    
    public String getOrderNumber() {
        return orderNumber;
    }

    public void setOrderNumber(String orderNumber) {
        this.orderNumber = orderNumber;
    }
    
    public String getCustomerId() {
        return customerId;
    }
    
    public void setCustomerId(String customerId) {
        this.customerId = customerId;
    }
    
    public DisputeType getDisputeType() {
        return disputeType;
    }
    
    public void setDisputeType(DisputeType disputeType) {
        this.disputeType = disputeType;
    }
    
    public DisputeStatus getStatus() {
        return status;
    }
    
    public void setStatus(DisputeStatus status) {
        this.status = status;
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
    
    public LocalDateTime getDisputeDate() {
        return disputeDate;
    }
    
    public void setDisputeDate(LocalDateTime disputeDate) {
        this.disputeDate = disputeDate;
    }
    
    public LocalDateTime getResolvedDate() {
        return resolvedDate;
    }
    
    public void setResolvedDate(LocalDateTime resolvedDate) {
        this.resolvedDate = resolvedDate;
    }
    
    public LocalDateTime getCreatedAt() {
        return createdAt;
    }
    
    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
    
    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }
    
    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
    
    @PreUpdate
    public void preUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
    
    @Schema(description = "Dispute type enumeration")
    public enum DisputeType {
        @Schema(description = "Duplicate charge dispute")
        DUPLICATE_CHARGE, 
        @Schema(description = "Unauthorized charge dispute")
        UNAUTHORIZED_CHARGE, 
        @Schema(description = "Product not received dispute")
        PRODUCT_NOT_RECEIVED, 
        @Schema(description = "Defective product dispute")
        DEFECTIVE_PRODUCT, 
        @Schema(description = "Billing error dispute")
        BILLING_ERROR
    }
    
    @Schema(description = "Dispute status enumeration")
    public enum DisputeStatus {
        @Schema(description = "Dispute is open")
        OPEN, 
        @Schema(description = "Dispute is in progress")
        IN_PROGRESS, 
        @Schema(description = "Dispute has been resolved")
        RESOLVED, 
        @Schema(description = "Dispute has been closed")
        CLOSED, 
        @Schema(description = "Dispute has been cancelled")
        CANCELLED
    }
}
