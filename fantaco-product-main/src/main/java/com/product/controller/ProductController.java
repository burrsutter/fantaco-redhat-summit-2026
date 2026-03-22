package com.product.controller;

import com.product.dto.ProductRequest;
import com.product.dto.ProductResponse;
import com.product.dto.ProductUpdateRequest;
import com.product.service.ProductService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/products")
@CrossOrigin(origins = "*")
@Tag(name = "Product", description = "Product catalog management operations")
public class ProductController {

    private static final Logger logger = LoggerFactory.getLogger(ProductController.class);

    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    @PostMapping
    @Operation(summary = "Create a new product",
               description = "Creates a new product record with the provided information")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Product created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "409", description = "Product SKU already exists")
    })
    public ResponseEntity<ProductResponse> createProduct(
            @Valid @RequestBody ProductRequest request) {
        logger.info("createProduct called with SKU: {}", request.sku());
        ProductResponse response = productService.createProduct(request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{sku}")
                .buildAndExpand(response.sku())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @GetMapping("/{sku}")
    @Operation(summary = "Get product by SKU",
               description = "Retrieves a single product record by its unique SKU identifier")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Product found"),
        @ApiResponse(responseCode = "404", description = "Product not found")
    })
    public ResponseEntity<ProductResponse> getProductBySku(
            @PathVariable String sku) {
        logger.info("getProductBySku called with SKU: {}", sku);
        ProductResponse response = productService.getProductById(sku);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    @Operation(summary = "Search products",
               description = "Search for products by name, category, or manufacturer with partial matching")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200",
                     description = "List of products matching the search criteria")
    })
    public ResponseEntity<List<ProductResponse>> searchProducts(
            @RequestParam(required = false) String name,
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String manufacturer) {
        logger.info("searchProducts called with name: {}, category: {}, manufacturer: {}",
                name, category, manufacturer);
        List<ProductResponse> products =
            productService.searchProducts(name, category, manufacturer);
        return ResponseEntity.ok(products);
    }

    @PutMapping("/{sku}")
    @Operation(summary = "Update product",
               description = "Updates an existing product record")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Product updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Product not found")
    })
    public ResponseEntity<ProductResponse> updateProduct(
            @PathVariable String sku,
            @Valid @RequestBody ProductUpdateRequest request) {
        logger.info("updateProduct called with SKU: {}", sku);
        ProductResponse response = productService.updateProduct(sku, request);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{sku}")
    @Operation(summary = "Delete product",
               description = "Permanently deletes a product record (hard delete)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Product deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Product not found")
    })
    public ResponseEntity<Void> deleteProduct(@PathVariable String sku) {
        logger.info("deleteProduct called with SKU: {}", sku);
        productService.deleteProduct(sku);
        return ResponseEntity.noContent().build();
    }
}
