package com.customer.repository;

import com.customer.model.SalesPerson;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface SalesPersonRepository extends JpaRepository<SalesPerson, Long> {
    List<SalesPerson> findByCustomerCustomerId(String customerId);
}
