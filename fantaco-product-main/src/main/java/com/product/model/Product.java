package com.product.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Objects;

@Entity
@Table(name = "product", indexes = {
    @Index(name = "idx_product_name", columnList = "name"),
    @Index(name = "idx_category", columnList = "category"),
    @Index(name = "idx_manufacturer", columnList = "manufacturer")
})
public class Product {

    @Id
    @Column(name = "sku", length = 20, nullable = false)
    @NotBlank(message = "SKU is required")
    @Size(max = 20, message = "SKU must not exceed 20 characters")
    private String sku;

    @Column(name = "name", nullable = false, length = 200)
    @NotBlank(message = "Product name is required")
    @Size(max = 200, message = "Product name must not exceed 200 characters")
    private String name;

    @Column(name = "description", length = 500)
    @Size(max = 500, message = "Description must not exceed 500 characters")
    private String description;

    @Column(name = "category", nullable = false, length = 50)
    @NotBlank(message = "Category is required")
    @Size(max = 50, message = "Category must not exceed 50 characters")
    private String category;

    @Column(name = "price", nullable = false, precision = 10, scale = 2)
    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than 0")
    private BigDecimal price;

    @Column(name = "cost", nullable = false, precision = 10, scale = 2)
    @NotNull(message = "Cost is required")
    @DecimalMin(value = "0.00", message = "Cost must be 0 or greater")
    private BigDecimal cost;

    @Column(name = "stock_quantity", nullable = false)
    @NotNull(message = "Stock quantity is required")
    @Min(value = 0, message = "Stock quantity must be 0 or greater")
    private Integer stockQuantity;

    @Column(name = "manufacturer", nullable = false, length = 100)
    @NotBlank(message = "Manufacturer is required")
    @Size(max = 100, message = "Manufacturer must not exceed 100 characters")
    private String manufacturer;

    @Column(name = "supplier", nullable = false, length = 100)
    @NotBlank(message = "Supplier is required")
    @Size(max = 100, message = "Supplier must not exceed 100 characters")
    private String supplier;

    @Column(name = "weight", precision = 10, scale = 2)
    @DecimalMin(value = "0.00", message = "Weight must be 0 or greater")
    private BigDecimal weight;

    @Column(name = "dimensions", length = 30)
    @Size(max = 30, message = "Dimensions must not exceed 30 characters")
    private String dimensions;

    @Column(name = "is_active", nullable = false)
    @NotNull(message = "Active status is required")
    private Boolean isActive;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    public Product() {
    }

    public Product(String sku, String name) {
        this.sku = sku;
        this.name = name;
    }

    // Getters and Setters
    public String getSku() {
        return sku;
    }

    public void setSku(String sku) {
        this.sku = sku;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public BigDecimal getPrice() {
        return price;
    }

    public void setPrice(BigDecimal price) {
        this.price = price;
    }

    public BigDecimal getCost() {
        return cost;
    }

    public void setCost(BigDecimal cost) {
        this.cost = cost;
    }

    public Integer getStockQuantity() {
        return stockQuantity;
    }

    public void setStockQuantity(Integer stockQuantity) {
        this.stockQuantity = stockQuantity;
    }

    public String getManufacturer() {
        return manufacturer;
    }

    public void setManufacturer(String manufacturer) {
        this.manufacturer = manufacturer;
    }

    public String getSupplier() {
        return supplier;
    }

    public void setSupplier(String supplier) {
        this.supplier = supplier;
    }

    public BigDecimal getWeight() {
        return weight;
    }

    public void setWeight(BigDecimal weight) {
        this.weight = weight;
    }

    public String getDimensions() {
        return dimensions;
    }

    public void setDimensions(String dimensions) {
        this.dimensions = dimensions;
    }

    public Boolean getIsActive() {
        return isActive;
    }

    public void setIsActive(Boolean isActive) {
        this.isActive = isActive;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Product product = (Product) o;
        return Objects.equals(sku, product.sku);
    }

    @Override
    public int hashCode() {
        return Objects.hash(sku);
    }

    @Override
    public String toString() {
        return "Product{" +
                "sku='" + sku + '\'' +
                ", name='" + name + '\'' +
                ", category='" + category + '\'' +
                '}';
    }
}
