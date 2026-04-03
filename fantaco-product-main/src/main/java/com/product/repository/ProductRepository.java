package com.product.repository;

import com.product.model.PodTheme;
import com.product.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProductRepository extends JpaRepository<Product, String> {

    List<Product> findByNameContainingIgnoreCase(String name);

    List<Product> findByCategoryContainingIgnoreCase(String category);

    List<Product> findByManufacturerContainingIgnoreCase(String manufacturer);

    /**
     * Products with no theme rows are treated as universal (fit any pod theme).
     */
    @Query("SELECT DISTINCT p FROM Product p WHERE SIZE(p.podThemes) = 0 OR :theme MEMBER OF p.podThemes")
    List<Product> findApplicableForTheme(@Param("theme") PodTheme theme);
}
