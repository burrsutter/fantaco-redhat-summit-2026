package com.product.service;

import com.product.dto.ProductRequest;
import com.product.dto.ProductResponse;
import com.product.dto.ProductUpdateRequest;
import com.product.exception.ProductNotFoundException;
import com.product.exception.DuplicateProductIdException;
import com.product.model.Product;
import com.product.repository.ProductRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

@Service
@Transactional
public class ProductService {

    private final ProductRepository productRepository;

    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public ProductResponse createProduct(ProductRequest request) {
        if (productRepository.existsById(request.sku())) {
            throw new DuplicateProductIdException(
                "Product with SKU " + request.sku() + " already exists");
        }

        Product product = new Product();
        product.setSku(request.sku());
        product.setName(request.name());
        product.setDescription(request.description());
        product.setCategory(request.category());
        product.setPrice(request.price());
        product.setCost(request.cost());
        product.setStockQuantity(request.stockQuantity());
        product.setManufacturer(request.manufacturer());
        product.setSupplier(request.supplier());
        product.setWeight(request.weight());
        product.setDimensions(request.dimensions());
        product.setIsActive(request.isActive());

        try {
            Product saved = productRepository.save(product);
            return toResponse(saved);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicateProductIdException(
                "Product with SKU " + request.sku() + " already exists");
        }
    }

    @Transactional(readOnly = true)
    public ProductResponse getProductById(String sku) {
        Product product = productRepository.findById(sku)
                .orElseThrow(() -> new ProductNotFoundException(
                    "Product with SKU " + sku + " not found"));
        return toResponse(product);
    }

    @Transactional(readOnly = true)
    public List<ProductResponse> searchProducts(String name, String category, String manufacturer) {
        boolean hasAnyCriteria = (name != null && !name.isBlank())
                || (category != null && !category.isBlank())
                || (manufacturer != null && !manufacturer.isBlank());

        if (!hasAnyCriteria) {
            return productRepository.findAll().stream()
                    .map(this::toResponse)
                    .toList();
        }

        List<Product> results = null;

        if (name != null && !name.isBlank()) {
            results = new ArrayList<>(
                productRepository.findByNameContainingIgnoreCase(name));
        }
        if (category != null && !category.isBlank()) {
            List<Product> matched =
                productRepository.findByCategoryContainingIgnoreCase(category);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }
        if (manufacturer != null && !manufacturer.isBlank()) {
            List<Product> matched =
                productRepository.findByManufacturerContainingIgnoreCase(manufacturer);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }

        return results.stream().map(this::toResponse).toList();
    }

    public ProductResponse updateProduct(String sku, ProductUpdateRequest request) {
        Product product = productRepository.findById(sku)
                .orElseThrow(() -> new ProductNotFoundException(
                    "Product with SKU " + sku + " not found"));

        product.setName(request.name());
        product.setDescription(request.description());
        product.setCategory(request.category());
        product.setPrice(request.price());
        product.setCost(request.cost());
        product.setStockQuantity(request.stockQuantity());
        product.setManufacturer(request.manufacturer());
        product.setSupplier(request.supplier());
        product.setWeight(request.weight());
        product.setDimensions(request.dimensions());
        product.setIsActive(request.isActive());

        Product updated = productRepository.save(product);
        return toResponse(updated);
    }

    public void deleteProduct(String sku) {
        if (!productRepository.existsById(sku)) {
            throw new ProductNotFoundException(
                "Product with SKU " + sku + " not found");
        }
        productRepository.deleteById(sku);
    }

    private List<Product> intersect(List<Product> a, List<Product> b) {
        List<Product> result = new ArrayList<>(a);
        result.retainAll(b);
        return result;
    }

    private ProductResponse toResponse(Product product) {
        return new ProductResponse(
                product.getSku(),
                product.getName(),
                product.getDescription(),
                product.getCategory(),
                product.getPrice(),
                product.getCost(),
                product.getStockQuantity(),
                product.getManufacturer(),
                product.getSupplier(),
                product.getWeight(),
                product.getDimensions(),
                product.getIsActive(),
                product.getCreatedAt(),
                product.getUpdatedAt()
        );
    }
}
