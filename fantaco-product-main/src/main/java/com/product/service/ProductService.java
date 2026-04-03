package com.product.service;

import com.product.dto.ProductRequest;
import com.product.dto.ProductResponse;
import com.product.dto.ProductUpdateRequest;
import com.product.exception.DuplicateProductIdException;
import com.product.exception.InvalidPodThemeException;
import com.product.exception.ProductNotFoundException;
import com.product.model.PodTheme;
import com.product.model.Product;
import com.product.repository.ProductRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

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
        product.setPodThemes(parsePodThemes(request.podThemes()));

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
    public List<ProductResponse> searchProducts(
            String name, String category, String manufacturer, String theme) {
        List<Product> candidates;
        if (theme != null && !theme.isBlank()) {
            PodTheme podTheme = parseSingleTheme(theme.trim());
            candidates = productRepository.findApplicableForTheme(podTheme);
        } else {
            candidates = productRepository.findAll();
        }

        boolean hasTextCriteria = (name != null && !name.isBlank())
                || (category != null && !category.isBlank())
                || (manufacturer != null && !manufacturer.isBlank());

        if (!hasTextCriteria) {
            return candidates.stream().map(this::toResponse).toList();
        }

        List<Product> results = new ArrayList<>(candidates);

        if (name != null && !name.isBlank()) {
            String needle = name.toLowerCase();
            results.removeIf(p -> !p.getName().toLowerCase().contains(needle));
        }
        if (category != null && !category.isBlank()) {
            String needle = category.toLowerCase();
            results.removeIf(p -> !p.getCategory().toLowerCase().contains(needle));
        }
        if (manufacturer != null && !manufacturer.isBlank()) {
            String needle = manufacturer.toLowerCase();
            results.removeIf(p -> !p.getManufacturer().toLowerCase().contains(needle));
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
        if (request.podThemes() != null) {
            product.setPodThemes(parsePodThemes(request.podThemes()));
        }

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

    private ProductResponse toResponse(Product product) {
        List<String> themeNames = product.getPodThemes().stream()
                .map(Enum::name)
                .sorted()
                .toList();
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
                themeNames,
                product.getCreatedAt(),
                product.getUpdatedAt()
        );
    }

    private static Set<PodTheme> parsePodThemes(List<String> raw) {
        if (raw == null || raw.isEmpty()) {
            return new LinkedHashSet<>();
        }
        LinkedHashSet<PodTheme> out = new LinkedHashSet<>();
        for (String s : raw) {
            if (s == null || s.isBlank()) {
                continue;
            }
            try {
                out.add(PodTheme.valueOf(s.trim()));
            } catch (IllegalArgumentException e) {
                throw new InvalidPodThemeException(
                        "Invalid pod theme '" + s + "'. Allowed: "
                                + Arrays.toString(PodTheme.values()));
            }
        }
        return out;
    }

    private static PodTheme parseSingleTheme(String token) {
        try {
            return PodTheme.valueOf(token);
        } catch (IllegalArgumentException e) {
            throw new InvalidPodThemeException(
                    "Invalid pod theme '" + token + "'. Allowed: "
                            + Arrays.stream(PodTheme.values())
                            .map(Enum::name)
                            .collect(Collectors.joining(", ")));
        }
    }
}
