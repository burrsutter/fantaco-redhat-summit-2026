package com.customer.controller;

import com.customer.dto.CustomerDetailResponse;
import com.customer.dto.CustomerRequest;
import com.customer.dto.CustomerResponse;
import com.customer.dto.CustomerUpdateRequest;
import com.customer.service.CustomerService;
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
@RequestMapping("/api/customers")
@Tag(name = "Customer", description = "Customer master data management operations")
public class CustomerController {

    private static final Logger logger = LoggerFactory.getLogger(CustomerController.class);

    private final CustomerService customerService;

    public CustomerController(CustomerService customerService) {
        this.customerService = customerService;
    }

    @PostMapping
    @Operation(summary = "Create a new customer", description = "Creates a new customer record with the provided information")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Customer created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "409", description = "Customer ID already exists")
    })
    public ResponseEntity<CustomerResponse> createCustomer(@Valid @RequestBody CustomerRequest request) {
        logger.info("createCustomer called with request: {}", request);
        CustomerResponse response = customerService.createCustomer(request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.customerId())
                .toUri();

        logger.info("createCustomer returning response: {}", response);
        return ResponseEntity.created(location).body(response);
    }

    @GetMapping("/{customerId}/detail")
    @Operation(summary = "Get customer detail", description = "Retrieves a customer with all CRM data (notes, contacts, sales persons)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Customer detail found"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<CustomerDetailResponse> getCustomerDetail(@PathVariable String customerId) {
        logger.info("getCustomerDetail called with customerId: {}", customerId);
        CustomerDetailResponse response = customerService.getCustomerDetailById(customerId);
        logger.info("getCustomerDetail returning response for customerId: {}", customerId);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{customerId}")
    @Operation(summary = "Get customer by ID", description = "Retrieves a single customer record by its unique identifier")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Customer found"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<CustomerResponse> getCustomerById(@PathVariable String customerId) {
        logger.info("getCustomerById called with customerId: {}", customerId);
        CustomerResponse response = customerService.getCustomerById(customerId);
        logger.info("getCustomerById returning response: {}", response);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    @Operation(summary = "Search customers", description = "Search for customers by various fields with partial matching")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "List of customers matching the search criteria")
    })
    public ResponseEntity<List<CustomerResponse>> searchCustomers(
            @RequestParam(required = false) String companyName,
            @RequestParam(required = false) String contactName,
            @RequestParam(required = false) String contactEmail,
            @RequestParam(required = false) String phone,
            @RequestParam(required = false) String salesPersonName) {
        logger.info("searchCustomers called with companyName: {}, contactName: {}, contactEmail: {}, phone: {}, salesPersonName: {}",
                companyName, contactName, contactEmail, phone, salesPersonName);
        List<CustomerResponse> customers = customerService.searchCustomers(companyName, contactName, contactEmail, phone, salesPersonName);
        logger.info("searchCustomers returning {} customers", customers.size());
        return ResponseEntity.ok(customers);
    }

    @PutMapping("/{customerId}")
    @Operation(summary = "Update customer", description = "Updates an existing customer record")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Customer updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<CustomerResponse> updateCustomer(
            @PathVariable String customerId,
            @Valid @RequestBody CustomerUpdateRequest request) {
        logger.info("updateCustomer called with customerId: {}, request: {}", customerId, request);
        CustomerResponse response = customerService.updateCustomer(customerId, request);
        logger.info("updateCustomer returning response: {}", response);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{customerId}")
    @Operation(summary = "Delete customer", description = "Permanently deletes a customer record (hard delete)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Customer deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<Void> deleteCustomer(@PathVariable String customerId) {
        logger.info("deleteCustomer called with customerId: {}", customerId);
        customerService.deleteCustomer(customerId);
        logger.info("deleteCustomer completed successfully for customerId: {}", customerId);
        return ResponseEntity.noContent().build();
    }
}
