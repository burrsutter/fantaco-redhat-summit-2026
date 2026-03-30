package com.fantaco.finance.entity;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.persistence.*;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "invoices")
@Schema(description = "Invoice entity representing a customer invoice")
public class Invoice {
    
    @Schema(description = "Unique identifier for the invoice", example = "1")
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Schema(description = "Unique invoice number", example = "INV-2024-001")
    @NotBlank
    @Column(name = "invoice_number", unique = true, nullable = false)
    private String invoiceNumber;
    
    @Schema(description = "Associated order number", example = "ORD-2025-0001")
    @NotBlank
    @Column(name = "order_number", nullable = false)
    private String orderNumber;
    
    @Schema(description = "Customer identifier", example = "CUST-12345")
    @NotBlank
    @Column(name = "customer_id", nullable = false)
    private String customerId;
    
    @Schema(description = "Invoice amount", example = "99.99")
    @NotNull
    @DecimalMin(value = "0.0", inclusive = false)
    @Column(name = "amount", nullable = false, precision = 10, scale = 2)
    private BigDecimal amount;
    
    @Schema(description = "Current status of the invoice", example = "PAID")
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private InvoiceStatus status;
    
    @Schema(description = "Date when the invoice was created", example = "2024-01-15T10:30:00")
    @Column(name = "invoice_date", nullable = false)
    private LocalDateTime invoiceDate;
    
    @Schema(description = "Due date for payment", example = "2024-02-15T23:59:59")
    @Column(name = "due_date")
    private LocalDateTime dueDate;
    
    @Schema(description = "Date when the invoice was paid", example = "2024-01-20T14:30:00")
    @Column(name = "paid_date")
    private LocalDateTime paidDate;
    
    @Schema(description = "Timestamp when the record was created", example = "2024-01-15T10:30:00")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
    
    @Schema(description = "Timestamp when the record was last updated", example = "2024-01-15T11:00:00")
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
    
    // Constructors
    public Invoice() {
        this.createdAt = LocalDateTime.now();
    }
    
    public Invoice(String invoiceNumber, String orderNumber, String customerId, BigDecimal amount, InvoiceStatus status) {
        this();
        this.invoiceNumber = invoiceNumber;
        this.orderNumber = orderNumber;
        this.customerId = customerId;
        this.amount = amount;
        this.status = status;
        this.invoiceDate = LocalDateTime.now();
    }
    
    // Getters and Setters
    public Long getId() {
        return id;
    }
    
    public void setId(Long id) {
        this.id = id;
    }
    
    public String getInvoiceNumber() {
        return invoiceNumber;
    }
    
    public void setInvoiceNumber(String invoiceNumber) {
        this.invoiceNumber = invoiceNumber;
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
    
    public BigDecimal getAmount() {
        return amount;
    }
    
    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }
    
    public InvoiceStatus getStatus() {
        return status;
    }
    
    public void setStatus(InvoiceStatus status) {
        this.status = status;
    }
    
    public LocalDateTime getInvoiceDate() {
        return invoiceDate;
    }
    
    public void setInvoiceDate(LocalDateTime invoiceDate) {
        this.invoiceDate = invoiceDate;
    }
    
    public LocalDateTime getDueDate() {
        return dueDate;
    }
    
    public void setDueDate(LocalDateTime dueDate) {
        this.dueDate = dueDate;
    }
    
    public LocalDateTime getPaidDate() {
        return paidDate;
    }
    
    public void setPaidDate(LocalDateTime paidDate) {
        this.paidDate = paidDate;
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
    
    @Schema(description = "Invoice status enumeration")
    public enum InvoiceStatus {
        @Schema(description = "Invoice is in draft status")
        DRAFT, 
        @Schema(description = "Invoice has been sent to customer")
        SENT, 
        @Schema(description = "Invoice has been paid")
        PAID, 
        @Schema(description = "Invoice is overdue")
        OVERDUE, 
        @Schema(description = "Invoice has been cancelled")
        CANCELLED, 
        @Schema(description = "Invoice has been refunded")
        REFUNDED
    }
}
