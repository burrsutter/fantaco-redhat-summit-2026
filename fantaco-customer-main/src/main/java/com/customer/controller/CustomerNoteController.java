package com.customer.controller;

import com.customer.dto.CustomerNoteRequest;
import com.customer.dto.CustomerNoteResponse;
import com.customer.service.CustomerNoteService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/customers/{customerId}/notes")
@Tag(name = "Customer Notes", description = "Customer notes management operations")
public class CustomerNoteController {

    private static final Logger logger = LoggerFactory.getLogger(CustomerNoteController.class);

    private final CustomerNoteService noteService;

    public CustomerNoteController(CustomerNoteService noteService) {
        this.noteService = noteService;
    }

    @GetMapping
    @Operation(summary = "Get all notes for a customer", description = "Retrieves all notes associated with a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Notes retrieved successfully"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<List<CustomerNoteResponse>> getNotes(@PathVariable String customerId) {
        logger.info("getNotes called for customerId: {}", customerId);
        List<CustomerNoteResponse> notes = noteService.getNotesByCustomerId(customerId);
        logger.info("getNotes returning {} notes for customerId: {}", notes.size(), customerId);
        return ResponseEntity.ok(notes);
    }

    @GetMapping("/{noteId}")
    @Operation(summary = "Get a specific note", description = "Retrieves a single note by its ID")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Note found"),
        @ApiResponse(responseCode = "404", description = "Customer or note not found")
    })
    public ResponseEntity<CustomerNoteResponse> getNoteById(
            @PathVariable String customerId,
            @PathVariable Long noteId) {
        logger.info("getNoteById called for customerId: {}, noteId: {}", customerId, noteId);
        CustomerNoteResponse response = noteService.getNoteById(customerId, noteId);
        return ResponseEntity.ok(response);
    }

    @PostMapping
    @Operation(summary = "Create a note", description = "Creates a new note for a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Note created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<CustomerNoteResponse> createNote(
            @PathVariable String customerId,
            @Valid @RequestBody CustomerNoteRequest request) {
        logger.info("createNote called for customerId: {}", customerId);
        CustomerNoteResponse response = noteService.createNote(customerId, request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.id())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @DeleteMapping("/{noteId}")
    @Operation(summary = "Delete a note", description = "Permanently deletes a note")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Note deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Customer or note not found")
    })
    public ResponseEntity<Void> deleteNote(
            @PathVariable String customerId,
            @PathVariable Long noteId) {
        logger.info("deleteNote called for customerId: {}, noteId: {}", customerId, noteId);
        noteService.deleteNote(customerId, noteId);
        return ResponseEntity.noContent().build();
    }
}
