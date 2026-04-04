package com.fantaco.it.repository;

import com.fantaco.it.entity.Ticket;
import com.fantaco.it.entity.Ticket.TicketCategory;
import com.fantaco.it.entity.Ticket.TicketStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface TicketRepository extends JpaRepository<Ticket, Long> {

    Optional<Ticket> findByTicketNumber(String ticketNumber);

    List<Ticket> findByStatusOrderByCreatedAtDesc(TicketStatus status);

    List<Ticket> findByCategoryOrderByCreatedAtDesc(TicketCategory category);

    List<Ticket> findBySubmittedByContainingIgnoreCaseOrderByCreatedAtDesc(String submittedBy);

    List<Ticket> findByAssignedToContainingIgnoreCaseOrderByCreatedAtDesc(String assignedTo);

    List<Ticket> findByStatusAndCategoryOrderByCreatedAtDesc(TicketStatus status, TicketCategory category);

    List<Ticket> findAllByOrderByCreatedAtDesc();

    long countByStatus(TicketStatus status);

    @Query("SELECT t FROM Ticket t ORDER BY t.ticketNumber DESC LIMIT 1")
    Optional<Ticket> findTopByOrderByTicketNumberDesc();
}
