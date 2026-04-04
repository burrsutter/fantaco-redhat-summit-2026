package com.customer.repository;

import com.customer.model.Customer;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CustomerRepository extends JpaRepository<Customer, String> {

    List<Customer> findByCompanyNameContainingIgnoreCase(String companyName);

    List<Customer> findByContactNameContainingIgnoreCase(String contactName);

    List<Customer> findByContactEmailContainingIgnoreCase(String contactEmail);

    List<Customer> findByPhoneContaining(String phone);

    List<Customer> findByPhoneContainingIgnoreCase(String phone);

    @Query("SELECT DISTINCT c FROM Customer c JOIN c.salesPersons sp " +
           "WHERE LOWER(sp.firstName) LIKE LOWER(CONCAT('%', :name, '%')) " +
           "OR LOWER(sp.lastName) LIKE LOWER(CONCAT('%', :name, '%'))")
    List<Customer> findBySalesPersonName(@Param("name") String name);
}
