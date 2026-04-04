package com.fantaco.it.controller;

import com.fantaco.it.dto.*;
import com.fantaco.it.entity.Ticket;
import com.fantaco.it.entity.TicketComment;
import com.fantaco.it.service.ItService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/it")
@CrossOrigin(origins = "*")
@Tag(name = "IT Ticketing API", description = "REST API for IT ticket management")
public class ItController {

    private static final Logger logger = LoggerFactory.getLogger(ItController.class);

    @Autowired
    private ItService itService;

    @Operation(summary = "Submit a new IT ticket", tags = {"Tickets"})
    @PostMapping(value = "/tickets/submit", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> submitTicket(@Valid @RequestBody SubmitTicketRequest request) {
        logger.info("submitTicket called with request: {}", request);
        try {
            Ticket ticket = itService.submitTicket(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Ticket submitted successfully");
            response.put("data", ticket);
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error submitting ticket: " + e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(summary = "List tickets with optional filters", tags = {"Tickets"})
    @PostMapping(value = "/tickets/list", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> listTickets(@RequestBody ListTicketsRequest request) {
        logger.info("listTickets called with request: {}", request);
        try {
            List<Ticket> tickets = itService.listTickets(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Tickets retrieved successfully");
            response.put("data", tickets);
            response.put("count", tickets.size());
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error listing tickets: " + e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(summary = "Get ticket details with comments", tags = {"Tickets"})
    @PostMapping(value = "/tickets/details", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> getTicketDetails(@Valid @RequestBody TicketDetailsRequest request) {
        logger.info("getTicketDetails called with request: {}", request);
        try {
            Map<String, Object> details = itService.getTicketDetails(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Ticket details retrieved successfully");
            response.put("data", details);
            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error retrieving ticket details: " + e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(summary = "Assign a ticket to IT staff", tags = {"Tickets"})
    @PostMapping(value = "/tickets/assign", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> assignTicket(@Valid @RequestBody AssignTicketRequest request) {
        logger.info("assignTicket called with request: {}", request);
        try {
            Ticket ticket = itService.assignTicket(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Ticket assigned successfully");
            response.put("data", ticket);
            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error assigning ticket: " + e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(summary = "Update ticket status", tags = {"Tickets"})
    @PostMapping(value = "/tickets/update-status", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> updateStatus(@Valid @RequestBody UpdateStatusRequest request) {
        logger.info("updateStatus called with request: {}", request);
        try {
            Ticket ticket = itService.updateStatus(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Ticket status updated successfully");
            response.put("data", ticket);
            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error updating ticket status: " + e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(summary = "Add a comment to a ticket", tags = {"Tickets"})
    @PostMapping(value = "/tickets/comment", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> addComment(@Valid @RequestBody AddCommentRequest request) {
        logger.info("addComment called with request: {}", request);
        try {
            TicketComment comment = itService.addComment(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Comment added successfully");
            response.put("data", comment);
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error adding comment: " + e.getMessage());
            errorResponse.put("data", null);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    int count = 0;

    @Operation(summary = "Health check endpoint", tags = {"Health"})
    @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> healthCheck() {
        logger.info("healthCheck called");
        count++;
        Map<String, Object> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "Fantaco IT Ticketing API");
        response.put("count", count);
        response.put("timestamp", java.time.LocalDateTime.now());
        return ResponseEntity.ok(response);
    }
}
