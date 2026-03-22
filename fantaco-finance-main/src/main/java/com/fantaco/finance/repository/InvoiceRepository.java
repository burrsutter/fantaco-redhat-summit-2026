package com.fantaco.finance.repository;

import com.fantaco.finance.entity.Invoice;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface InvoiceRepository extends JpaRepository<Invoice, Long> {

    List<Invoice> findByCustomerIdOrderByInvoiceDateDesc(String customerId);

    List<Invoice> findByCustomerIdAndInvoiceDateBetweenOrderByInvoiceDateDesc(
            String customerId, LocalDateTime startDate, LocalDateTime endDate);

    List<Invoice> findByStatusOrderByInvoiceDateDesc(Invoice.InvoiceStatus status);

    List<Invoice> findByOrderNumberOrderByInvoiceDateDesc(String orderNumber);

    @Query("SELECT i FROM Invoice i WHERE i.customerId = :customerId AND i.invoiceDate >= :startDate ORDER BY i.invoiceDate DESC")
    List<Invoice> findRecentInvoicesByCustomer(@Param("customerId") String customerId, @Param("startDate") LocalDateTime startDate);

    boolean existsByInvoiceNumber(String invoiceNumber);
}
