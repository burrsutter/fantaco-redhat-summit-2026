package com.customer.controller;

import com.customer.dto.SalesPersonRequest;
import com.customer.dto.SalesPersonResponse;
import com.customer.service.SalesPersonService;
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
@RequestMapping("/api/customers/{customerId}/salespersons")
@Tag(name = "Sales Persons", description = "Sales person management operations")
public class SalesPersonController {

    private static final Logger logger = LoggerFactory.getLogger(SalesPersonController.class);

    private final SalesPersonService salesPersonService;

    public SalesPersonController(SalesPersonService salesPersonService) {
        this.salesPersonService = salesPersonService;
    }

    @GetMapping
    @Operation(summary = "Get all sales persons for a customer", description = "Retrieves all sales persons assigned to a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Sales persons retrieved successfully"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<List<SalesPersonResponse>> getSalesPersons(@PathVariable String customerId) {
        logger.info("getSalesPersons called for customerId: {}", customerId);
        List<SalesPersonResponse> salesPersons = salesPersonService.getSalesPersonsByCustomerId(customerId);
        logger.info("getSalesPersons returning {} sales persons for customerId: {}", salesPersons.size(), customerId);
        return ResponseEntity.ok(salesPersons);
    }

    @GetMapping("/{salesPersonId}")
    @Operation(summary = "Get a specific sales person", description = "Retrieves a single sales person by its ID")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Sales person found"),
        @ApiResponse(responseCode = "404", description = "Customer or sales person not found")
    })
    public ResponseEntity<SalesPersonResponse> getSalesPersonById(
            @PathVariable String customerId,
            @PathVariable Long salesPersonId) {
        logger.info("getSalesPersonById called for customerId: {}, salesPersonId: {}", customerId, salesPersonId);
        SalesPersonResponse response = salesPersonService.getSalesPersonById(customerId, salesPersonId);
        return ResponseEntity.ok(response);
    }

    @PostMapping
    @Operation(summary = "Create a sales person", description = "Assigns a new sales person to a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Sales person created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<SalesPersonResponse> createSalesPerson(
            @PathVariable String customerId,
            @Valid @RequestBody SalesPersonRequest request) {
        logger.info("createSalesPerson called for customerId: {}", customerId);
        SalesPersonResponse response = salesPersonService.createSalesPerson(customerId, request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.id())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @PutMapping("/{salesPersonId}")
    @Operation(summary = "Update a sales person", description = "Updates an existing sales person assignment")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Sales person updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer or sales person not found")
    })
    public ResponseEntity<SalesPersonResponse> updateSalesPerson(
            @PathVariable String customerId,
            @PathVariable Long salesPersonId,
            @Valid @RequestBody SalesPersonRequest request) {
        logger.info("updateSalesPerson called for customerId: {}, salesPersonId: {}", customerId, salesPersonId);
        SalesPersonResponse response = salesPersonService.updateSalesPerson(customerId, salesPersonId, request);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{salesPersonId}")
    @Operation(summary = "Delete a sales person", description = "Removes a sales person assignment from a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Sales person deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Customer or sales person not found")
    })
    public ResponseEntity<Void> deleteSalesPerson(
            @PathVariable String customerId,
            @PathVariable Long salesPersonId) {
        logger.info("deleteSalesPerson called for customerId: {}, salesPersonId: {}", customerId, salesPersonId);
        salesPersonService.deleteSalesPerson(customerId, salesPersonId);
        return ResponseEntity.noContent().build();
    }
}
