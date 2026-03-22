package com.fantaco.finance.repository;

import com.fantaco.finance.entity.Dispute;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface DisputeRepository extends JpaRepository<Dispute, Long> {

    List<Dispute> findByCustomerIdOrderByDisputeDateDesc(String customerId);

    List<Dispute> findByOrderNumberOrderByDisputeDateDesc(String orderNumber);

    List<Dispute> findByStatusOrderByDisputeDateDesc(Dispute.DisputeStatus status);

    List<Dispute> findByDisputeTypeOrderByDisputeDateDesc(Dispute.DisputeType disputeType);

    @Query("SELECT d FROM Dispute d WHERE d.customerId = :customerId AND d.disputeDate >= :startDate ORDER BY d.disputeDate DESC")
    List<Dispute> findRecentDisputesByCustomer(@Param("customerId") String customerId, @Param("startDate") LocalDateTime startDate);

    boolean existsByDisputeNumber(String disputeNumber);

    @Query("SELECT COUNT(d) FROM Dispute d WHERE d.orderNumber = :orderNumber AND d.disputeType = :disputeType AND d.status IN ('OPEN', 'IN_PROGRESS')")
    long countActiveDisputesByOrderAndType(@Param("orderNumber") String orderNumber, @Param("disputeType") Dispute.DisputeType disputeType);
}
