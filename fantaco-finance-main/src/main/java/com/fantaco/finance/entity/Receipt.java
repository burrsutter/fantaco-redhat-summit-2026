package com.fantaco.finance.entity;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import java.time.LocalDateTime;

@Entity
@Table(name = "receipts")
@Schema(description = "Receipt entity representing a customer receipt")
public class Receipt {
    
    @Schema(description = "Unique identifier for the receipt", example = "1")
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Schema(description = "Unique receipt number", example = "RCP-2024-001")
    @NotBlank
    @Column(name = "receipt_number", unique = true, nullable = false)
    private String receiptNumber;
    
    @Schema(description = "Associated order number", example = "ORD-2024-0001")
    @NotBlank
    @Column(name = "order_number", nullable = false)
    private String orderNumber;
    
    @Schema(description = "Customer identifier", example = "CUST-12345")
    @NotBlank
    @Column(name = "customer_id", nullable = false)
    private String customerId;
    
    @Schema(description = "Current status of the receipt", example = "FOUND")
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private ReceiptStatus status;
    
    @Schema(description = "File path for the receipt", example = "/receipts/2024/01/15/rcp-001.pdf")
    @Column(name = "file_path")
    private String filePath;
    
    @Schema(description = "Original file name", example = "receipt-001.pdf")
    @Column(name = "file_name")
    private String fileName;
    
    @Schema(description = "File size in bytes", example = "1024")
    @Column(name = "file_size")
    private Long fileSize;
    
    @Schema(description = "MIME type of the file", example = "application/pdf")
    @Column(name = "mime_type")
    private String mimeType;
    
    @Schema(description = "Date when the receipt was created", example = "2024-01-15T10:30:00")
    @Column(name = "receipt_date", nullable = false)
    private LocalDateTime receiptDate;
    
    @Schema(description = "Timestamp when the record was created", example = "2024-01-15T10:30:00")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
    
    @Schema(description = "Timestamp when the record was last updated", example = "2024-01-15T11:00:00")
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
    
    // Constructors
    public Receipt() {
        this.createdAt = LocalDateTime.now();
    }
    
    public Receipt(String receiptNumber, String orderNumber, String customerId, ReceiptStatus status) {
        this();
        this.receiptNumber = receiptNumber;
        this.orderNumber = orderNumber;
        this.customerId = customerId;
        this.status = status;
        this.receiptDate = LocalDateTime.now();
    }
    
    // Getters and Setters
    public Long getId() {
        return id;
    }
    
    public void setId(Long id) {
        this.id = id;
    }
    
    public String getReceiptNumber() {
        return receiptNumber;
    }
    
    public void setReceiptNumber(String receiptNumber) {
        this.receiptNumber = receiptNumber;
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
    
    public ReceiptStatus getStatus() {
        return status;
    }
    
    public void setStatus(ReceiptStatus status) {
        this.status = status;
    }
    
    public String getFilePath() {
        return filePath;
    }
    
    public void setFilePath(String filePath) {
        this.filePath = filePath;
    }
    
    public String getFileName() {
        return fileName;
    }
    
    public void setFileName(String fileName) {
        this.fileName = fileName;
    }
    
    public Long getFileSize() {
        return fileSize;
    }
    
    public void setFileSize(Long fileSize) {
        this.fileSize = fileSize;
    }
    
    public String getMimeType() {
        return mimeType;
    }
    
    public void setMimeType(String mimeType) {
        this.mimeType = mimeType;
    }
    
    public LocalDateTime getReceiptDate() {
        return receiptDate;
    }
    
    public void setReceiptDate(LocalDateTime receiptDate) {
        this.receiptDate = receiptDate;
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
    
    @Schema(description = "Receipt status enumeration")
    public enum ReceiptStatus {
        @Schema(description = "Receipt is pending")
        PENDING, 
        @Schema(description = "Receipt has been found")
        FOUND, 
        @Schema(description = "Receipt is lost")
        LOST, 
        @Schema(description = "Receipt has been regenerated")
        REGENERATED, 
        @Schema(description = "Receipt has been cancelled")
        CANCELLED
    }
}
