package com.salesorder.repository;

import com.salesorder.model.SalesOrder;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface SalesOrderRepository extends JpaRepository<SalesOrder, String> {

    List<SalesOrder> findByCustomerIdContainingIgnoreCase(String customerId);

    List<SalesOrder> findByCustomerNameContainingIgnoreCase(String customerName);

    List<SalesOrder> findByStatusContainingIgnoreCase(String status);
}
