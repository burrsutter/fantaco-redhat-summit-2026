package com.salesorder.controller;

import com.salesorder.dto.SalesOrderRequest;
import com.salesorder.dto.SalesOrderResponse;
import com.salesorder.dto.SalesOrderUpdateRequest;
import com.salesorder.service.SalesOrderService;
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
@RequestMapping("/api/sales-orders")
@CrossOrigin(origins = "*")
@Tag(name = "SalesOrder", description = "Sales order management operations")
public class SalesOrderController {

    private static final Logger logger = LoggerFactory.getLogger(SalesOrderController.class);

    private final SalesOrderService salesOrderService;

    public SalesOrderController(SalesOrderService salesOrderService) {
        this.salesOrderService = salesOrderService;
    }

    @PostMapping
    @Operation(summary = "Create a new sales order",
               description = "Creates a new sales order with line items")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Sales order created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "409", description = "Order number already exists")
    })
    public ResponseEntity<SalesOrderResponse> createSalesOrder(
            @Valid @RequestBody SalesOrderRequest request) {
        logger.info("createSalesOrder called with order number: {}", request.orderNumber());
        SalesOrderResponse response = salesOrderService.createSalesOrder(request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{orderNumber}")
                .buildAndExpand(response.orderNumber())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @GetMapping("/{orderNumber}")
    @Operation(summary = "Get sales order by order number",
               description = "Retrieves a single sales order with all line items")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Sales order found"),
        @ApiResponse(responseCode = "404", description = "Sales order not found")
    })
    public ResponseEntity<SalesOrderResponse> getSalesOrderByOrderNumber(
            @PathVariable String orderNumber) {
        logger.info("getSalesOrderByOrderNumber called with: {}", orderNumber);
        SalesOrderResponse response = salesOrderService.getSalesOrderById(orderNumber);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    @Operation(summary = "Search sales orders",
               description = "Search for sales orders by customer ID, customer name, or status")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200",
                     description = "List of sales orders matching the search criteria")
    })
    public ResponseEntity<List<SalesOrderResponse>> searchSalesOrders(
            @RequestParam(required = false) String customerId,
            @RequestParam(required = false) String customerName,
            @RequestParam(required = false) String status) {
        logger.info("searchSalesOrders called with customerId: {}, customerName: {}, status: {}",
                customerId, customerName, status);
        List<SalesOrderResponse> orders =
            salesOrderService.searchSalesOrders(customerId, customerName, status);
        return ResponseEntity.ok(orders);
    }

    @PutMapping("/{orderNumber}")
    @Operation(summary = "Update sales order",
               description = "Updates an existing sales order and replaces all line items")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Sales order updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Sales order not found")
    })
    public ResponseEntity<SalesOrderResponse> updateSalesOrder(
            @PathVariable String orderNumber,
            @Valid @RequestBody SalesOrderUpdateRequest request) {
        logger.info("updateSalesOrder called with order number: {}", orderNumber);
        SalesOrderResponse response = salesOrderService.updateSalesOrder(orderNumber, request);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{orderNumber}")
    @Operation(summary = "Delete sales order",
               description = "Permanently deletes a sales order and all its line items (hard delete)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Sales order deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Sales order not found")
    })
    public ResponseEntity<Void> deleteSalesOrder(@PathVariable String orderNumber) {
        logger.info("deleteSalesOrder called with order number: {}", orderNumber);
        salesOrderService.deleteSalesOrder(orderNumber);
        return ResponseEntity.noContent().build();
    }
}
