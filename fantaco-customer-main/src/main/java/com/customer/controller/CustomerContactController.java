package com.customer.controller;

import com.customer.dto.CustomerContactRequest;
import com.customer.dto.CustomerContactResponse;
import com.customer.service.CustomerContactService;
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
@RequestMapping("/api/customers/{customerId}/contacts")
@Tag(name = "Customer Contacts", description = "Customer contacts management operations")
public class CustomerContactController {

    private static final Logger logger = LoggerFactory.getLogger(CustomerContactController.class);

    private final CustomerContactService contactService;

    public CustomerContactController(CustomerContactService contactService) {
        this.contactService = contactService;
    }

    @GetMapping
    @Operation(summary = "Get all contacts for a customer", description = "Retrieves all contacts associated with a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Contacts retrieved successfully"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<List<CustomerContactResponse>> getContacts(@PathVariable String customerId) {
        logger.info("getContacts called for customerId: {}", customerId);
        List<CustomerContactResponse> contacts = contactService.getContactsByCustomerId(customerId);
        logger.info("getContacts returning {} contacts for customerId: {}", contacts.size(), customerId);
        return ResponseEntity.ok(contacts);
    }

    @GetMapping("/{contactId}")
    @Operation(summary = "Get a specific contact", description = "Retrieves a single contact by its ID")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Contact found"),
        @ApiResponse(responseCode = "404", description = "Customer or contact not found")
    })
    public ResponseEntity<CustomerContactResponse> getContactById(
            @PathVariable String customerId,
            @PathVariable Long contactId) {
        logger.info("getContactById called for customerId: {}, contactId: {}", customerId, contactId);
        CustomerContactResponse response = contactService.getContactById(customerId, contactId);
        return ResponseEntity.ok(response);
    }

    @PostMapping
    @Operation(summary = "Create a contact", description = "Creates a new contact for a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Contact created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<CustomerContactResponse> createContact(
            @PathVariable String customerId,
            @Valid @RequestBody CustomerContactRequest request) {
        logger.info("createContact called for customerId: {}", customerId);
        CustomerContactResponse response = contactService.createContact(customerId, request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.id())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @PutMapping("/{contactId}")
    @Operation(summary = "Update a contact", description = "Updates an existing contact")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Contact updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer or contact not found")
    })
    public ResponseEntity<CustomerContactResponse> updateContact(
            @PathVariable String customerId,
            @PathVariable Long contactId,
            @Valid @RequestBody CustomerContactRequest request) {
        logger.info("updateContact called for customerId: {}, contactId: {}", customerId, contactId);
        CustomerContactResponse response = contactService.updateContact(customerId, contactId, request);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{contactId}")
    @Operation(summary = "Delete a contact", description = "Permanently deletes a contact")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Contact deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Customer or contact not found")
    })
    public ResponseEntity<Void> deleteContact(
            @PathVariable String customerId,
            @PathVariable Long contactId) {
        logger.info("deleteContact called for customerId: {}, contactId: {}", customerId, contactId);
        contactService.deleteContact(customerId, contactId);
        return ResponseEntity.noContent().build();
    }
}
