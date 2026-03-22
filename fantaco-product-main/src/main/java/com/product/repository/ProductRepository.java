package com.product.repository;

import com.product.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProductRepository extends JpaRepository<Product, String> {

    List<Product> findByNameContainingIgnoreCase(String name);

    List<Product> findByCategoryContainingIgnoreCase(String category);

    List<Product> findByManufacturerContainingIgnoreCase(String manufacturer);
}
