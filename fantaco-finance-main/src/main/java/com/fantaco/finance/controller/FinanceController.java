package com.fantaco.finance.controller;

import com.fantaco.finance.dto.*;
import com.fantaco.finance.entity.*;
import com.fantaco.finance.service.FinanceService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
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
@RequestMapping("/api/finance")
@CrossOrigin(origins = "*")
@Tag(name = "Finance API", description = "REST API for invoice, dispute, and receipt management")
public class FinanceController {

    private static final Logger logger = LoggerFactory.getLogger(FinanceController.class);

    @Autowired
    private FinanceService financeService;

    @Operation(
        summary = "List all invoices",
        description = "Retrieves all invoices in the system",
        tags = {"Invoices"}
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "200",
            description = "Invoices retrieved successfully",
            content = @Content(
                mediaType = MediaType.APPLICATION_JSON_VALUE,
                schema = @Schema(implementation = Map.class),
                examples = @ExampleObject(
                    name = "Success Response",
                    value = """
                    {
                        "success": true,
                        "message": "Invoices retrieved successfully",
                        "data": [
                            {
                                "id": 1,
                                "invoiceNumber": "INV-2024-001",
                                "orderNumber": "ORD-2024-0001",
                                "customerId": "CUST001",
                                "amount": 649.99,
                                "status": "PAID",
                                "invoiceDate": "2024-01-15T10:30:00"
                            }
                        ],
                        "count": 1
                    }
                    """
                )
            )
        )
    })
    @GetMapping(
        value = "/invoices",
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> getAllInvoices() {
        logger.info("getAllInvoices called");
        try {
            List<Invoice> invoices = financeService.getAllInvoices();

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Invoices retrieved successfully");
            response.put("data", invoices);
            response.put("count", invoices.size());

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error retrieving invoices: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Get invoice by ID",
        description = "Retrieves a specific invoice by its ID",
        tags = {"Invoices"}
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Invoice found"),
        @ApiResponse(responseCode = "404", description = "Invoice not found")
    })
    @GetMapping(
        value = "/invoices/{id}",
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> getInvoiceById(
        @Parameter(description = "Invoice ID", required = true)
        @PathVariable Long id) {
        logger.info("getInvoiceById called with id: {}", id);
        try {
            return financeService.getInvoiceById(id)
                .map(invoice -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("success", true);
                    response.put("message", "Invoice found");
                    response.put("data", invoice);
                    return ResponseEntity.ok(response);
                })
                .orElseGet(() -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("success", false);
                    response.put("message", "Invoice not found with ID: " + id);
                    response.put("data", null);
                    return ResponseEntity.status(HttpStatus.NOT_FOUND).body(response);
                });
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error retrieving invoice: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Get invoices by customer ID",
        description = "Retrieves all invoices for a specific customer",
        tags = {"Invoices"}
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Invoices retrieved successfully")
    })
    @GetMapping(
        value = "/invoices/customer/{customerId}",
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> getInvoicesByCustomerId(
        @Parameter(description = "Customer ID (e.g., CUST001)", required = true)
        @PathVariable String customerId) {
        logger.info("getInvoicesByCustomerId called with customerId: {}", customerId);
        try {
            List<Invoice> invoices = financeService.getInvoicesByCustomerId(customerId);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Invoices retrieved successfully");
            response.put("data", invoices);
            response.put("count", invoices.size());

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error retrieving invoices: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Get invoices by order number",
        description = "Retrieves all invoices for a specific order",
        tags = {"Invoices"}
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Invoices retrieved successfully")
    })
    @GetMapping(
        value = "/invoices/order/{orderNumber}",
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> getInvoicesByOrderNumber(
        @Parameter(description = "Order number (e.g., ORD-2024-0001)", required = true)
        @PathVariable String orderNumber) {
        logger.info("getInvoicesByOrderNumber called with orderNumber: {}", orderNumber);
        try {
            List<Invoice> invoices = financeService.getInvoicesByOrderNumber(orderNumber);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Invoices retrieved successfully");
            response.put("data", invoices);
            response.put("count", invoices.size());

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error retrieving invoices: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Get invoice history for a customer",
        description = "Retrieves the invoice history for a specific customer with optional date filtering and pagination",
        tags = {"Invoices"}
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "200",
            description = "Invoice history retrieved successfully",
            content = @Content(
                mediaType = MediaType.APPLICATION_JSON_VALUE,
                schema = @Schema(implementation = Map.class),
                examples = @ExampleObject(
                    name = "Success Response",
                    value = """
                    {
                        "success": true,
                        "message": "Invoice history retrieved successfully",
                        "data": [
                            {
                                "id": 1,
                                "invoiceNumber": "INV-2024-001",
                                "orderNumber": "ORD-2024-0001",
                                "customerId": "CUST001",
                                "amount": 649.99,
                                "status": "PAID",
                                "invoiceDate": "2024-01-15T10:30:00",
                                "dueDate": "2024-02-15T23:59:59",
                                "paidDate": "2024-01-20T14:30:00"
                            }
                        ],
                        "count": 1
                    }
                    """
                )
            )
        ),
        @ApiResponse(responseCode = "400", description = "Bad request - Invalid input data"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping(
        value = "/invoices/history",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> getInvoiceHistory(
        @Parameter(description = "Invoice history request parameters", required = true)
        @Valid @RequestBody InvoiceHistoryRequest request) {
        logger.info("getInvoiceHistory called with request: {}", request);
        try {
            List<Invoice> invoices = financeService.getInvoiceHistory(request);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Invoice history retrieved successfully");
            response.put("data", invoices);
            response.put("count", invoices.size());

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error retrieving invoice history: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Start a duplicate charge dispute",
        description = "Creates a new dispute for a duplicate charge issue reported by a customer",
        tags = {"Disputes"}
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "201",
            description = "Duplicate charge dispute started successfully",
            content = @Content(
                mediaType = MediaType.APPLICATION_JSON_VALUE,
                schema = @Schema(implementation = Map.class),
                examples = @ExampleObject(
                    name = "Success Response",
                    value = """
                    {
                        "success": true,
                        "message": "Duplicate charge dispute started successfully",
                        "data": {
                            "id": 1,
                            "disputeNumber": "DISP-2024-001",
                            "orderNumber": "ORD-2024-0001",
                            "customerId": "CUST001",
                            "disputeType": "DUPLICATE_CHARGE",
                            "status": "OPEN",
                            "description": "I was charged twice for the same order",
                            "reason": "DUPLICATE_PAYMENT"
                        }
                    }
                    """
                )
            )
        ),
        @ApiResponse(responseCode = "400", description = "Bad request - Invalid input data or business rule violation"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping(
        value = "/disputes/duplicate-charge",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> startDuplicateChargeDispute(
        @Parameter(description = "Duplicate charge dispute request parameters", required = true)
        @Valid @RequestBody DuplicateChargeDisputeRequest request) {
        logger.info("startDuplicateChargeDispute called with request: {}", request);
        try {
            Dispute dispute = financeService.startDuplicateChargeDispute(request);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Duplicate charge dispute started successfully");
            response.put("data", dispute);

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
            errorResponse.put("message", "Error starting duplicate charge dispute: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Find or regenerate a lost receipt",
        description = "Attempts to find an existing receipt or creates a new one for a lost receipt request",
        tags = {"Receipts"}
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "200",
            description = "Lost receipt found/created successfully",
            content = @Content(
                mediaType = MediaType.APPLICATION_JSON_VALUE,
                schema = @Schema(implementation = Map.class),
                examples = @ExampleObject(
                    name = "Success Response",
                    value = """
                    {
                        "success": true,
                        "message": "Lost receipt found/created successfully",
                        "data": {
                            "id": 1,
                            "receiptNumber": "RCPT-001",
                            "orderNumber": "ORD-2024-0001",
                            "customerId": "CUST001",
                            "status": "FOUND",
                            "filePath": "/receipts/2024/01/rcpt-001.pdf",
                            "fileName": "receipt-001.pdf",
                            "fileSize": 245760,
                            "mimeType": "application/pdf"
                        }
                    }
                    """
                )
            )
        ),
        @ApiResponse(responseCode = "400", description = "Bad request - Invalid input data"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping(
        value = "/receipts/find-lost",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> findLostReceipt(
        @Parameter(description = "Find lost receipt request parameters", required = true)
        @Valid @RequestBody FindLostReceiptRequest request) {
        logger.info("findLostReceipt called with request: {}", request);
        try {
            Receipt receipt = financeService.findLostReceipt(request);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Lost receipt found/created successfully");
            response.put("data", receipt);

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
            errorResponse.put("message", "Error finding lost receipt: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    int count = 0;

    @Operation(
        summary = "Health check endpoint",
        description = "Returns the current health status of the Finance API service",
        tags = {"Health"}
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "200",
            description = "Service is healthy",
            content = @Content(
                mediaType = MediaType.APPLICATION_JSON_VALUE,
                schema = @Schema(implementation = Map.class),
                examples = @ExampleObject(
                    name = "Success Response",
                    value = """
                    {
                        "status": "UP",
                        "service": "Fantaco Finance API",
                        "count": 1,
                        "timestamp": "2024-01-15T10:30:00"
                    }
                    """
                )
            )
        )
    })
    @GetMapping(
        value = "/health",
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> healthCheck() {
        logger.info("healthCheck called");
        count++;
        Map<String, Object> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "Fantaco Finance API");
        response.put("count", count);
        response.put("timestamp", java.time.LocalDateTime.now());

        return ResponseEntity.ok(response);
    }
}
