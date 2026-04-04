package com.fantaco.it.service;

import com.fantaco.it.dto.*;
import com.fantaco.it.entity.Ticket;
import com.fantaco.it.entity.Ticket.TicketCategory;
import com.fantaco.it.entity.Ticket.TicketPriority;
import com.fantaco.it.entity.Ticket.TicketStatus;
import com.fantaco.it.entity.TicketComment;
import com.fantaco.it.repository.TicketCommentRepository;
import com.fantaco.it.repository.TicketRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
@Transactional
public class ItService {

    @Autowired
    private TicketRepository ticketRepository;

    @Autowired
    private TicketCommentRepository ticketCommentRepository;

    public Ticket submitTicket(SubmitTicketRequest request) {
        // Generate ticket number from max existing
        long nextNum = ticketRepository.findTopByOrderByTicketNumberDesc()
                .map(t -> {
                    String num = t.getTicketNumber().replace("TKT-", "");
                    return Long.parseLong(num) + 1;
                })
                .orElse(1L);
        String ticketNumber = String.format("TKT-%05d", nextNum);

        Ticket ticket = new Ticket(
                ticketNumber,
                request.getTitle(),
                request.getDescription(),
                TicketCategory.valueOf(request.getCategory().toUpperCase()),
                TicketPriority.valueOf(request.getPriority().toUpperCase()),
                request.getSubmittedBy(),
                request.getSubmittedByEmail()
        );

        return ticketRepository.save(ticket);
    }

    @Transactional(readOnly = true)
    public List<Ticket> listTickets(ListTicketsRequest request) {
        // If both status and category are provided
        if (request.getStatus() != null && !request.getStatus().isBlank()
                && request.getCategory() != null && !request.getCategory().isBlank()) {
            TicketStatus status = TicketStatus.valueOf(request.getStatus().toUpperCase());
            TicketCategory category = TicketCategory.valueOf(request.getCategory().toUpperCase());
            return ticketRepository.findByStatusAndCategoryOrderByCreatedAtDesc(status, category);
        }

        // Status only
        if (request.getStatus() != null && !request.getStatus().isBlank()) {
            TicketStatus status = TicketStatus.valueOf(request.getStatus().toUpperCase());
            return ticketRepository.findByStatusOrderByCreatedAtDesc(status);
        }

        // Category only
        if (request.getCategory() != null && !request.getCategory().isBlank()) {
            TicketCategory category = TicketCategory.valueOf(request.getCategory().toUpperCase());
            return ticketRepository.findByCategoryOrderByCreatedAtDesc(category);
        }

        // Submitted by
        if (request.getSubmittedBy() != null && !request.getSubmittedBy().isBlank()) {
            return ticketRepository.findBySubmittedByContainingIgnoreCaseOrderByCreatedAtDesc(request.getSubmittedBy());
        }

        // Assigned to
        if (request.getAssignedTo() != null && !request.getAssignedTo().isBlank()) {
            return ticketRepository.findByAssignedToContainingIgnoreCaseOrderByCreatedAtDesc(request.getAssignedTo());
        }

        // No filters — return all
        return ticketRepository.findAllByOrderByCreatedAtDesc();
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getTicketDetails(TicketDetailsRequest request) {
        Ticket ticket = ticketRepository.findByTicketNumber(request.getTicketNumber())
                .orElseThrow(() -> new RuntimeException("Ticket not found: " + request.getTicketNumber()));

        List<TicketComment> comments = ticketCommentRepository.findByTicketIdOrderByCreatedAtAsc(ticket.getId());

        Map<String, Object> details = new HashMap<>();
        details.put("ticket", ticket);
        details.put("comments", comments);
        return details;
    }

    public Ticket assignTicket(AssignTicketRequest request) {
        Ticket ticket = ticketRepository.findByTicketNumber(request.getTicketNumber())
                .orElseThrow(() -> new RuntimeException("Ticket not found: " + request.getTicketNumber()));

        ticket.setAssignedTo(request.getAssignedTo());
        if (ticket.getStatus() == TicketStatus.OPEN) {
            ticket.setStatus(TicketStatus.IN_PROGRESS);
        }

        return ticketRepository.save(ticket);
    }

    public Ticket updateStatus(UpdateStatusRequest request) {
        Ticket ticket = ticketRepository.findByTicketNumber(request.getTicketNumber())
                .orElseThrow(() -> new RuntimeException("Ticket not found: " + request.getTicketNumber()));

        TicketStatus newStatus = TicketStatus.valueOf(request.getStatus().toUpperCase());
        ticket.setStatus(newStatus);

        if (newStatus == TicketStatus.RESOLVED || newStatus == TicketStatus.CLOSED) {
            ticket.setResolvedAt(LocalDateTime.now());
        }

        // If a resolution note is provided, add it as a comment
        if (request.getResolution() != null && !request.getResolution().isBlank()) {
            String author = ticket.getAssignedTo() != null ? ticket.getAssignedTo() : "System";
            TicketComment comment = new TicketComment(ticket.getId(), author, request.getResolution());
            ticketCommentRepository.save(comment);
        }

        return ticketRepository.save(ticket);
    }

    public TicketComment addComment(AddCommentRequest request) {
        Ticket ticket = ticketRepository.findByTicketNumber(request.getTicketNumber())
                .orElseThrow(() -> new RuntimeException("Ticket not found: " + request.getTicketNumber()));

        TicketComment comment = new TicketComment(ticket.getId(), request.getAuthor(), request.getBody());
        return ticketCommentRepository.save(comment);
    }
}
