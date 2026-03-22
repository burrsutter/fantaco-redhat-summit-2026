package com.salesorder.service;

import com.salesorder.dto.*;
import com.salesorder.exception.SalesOrderNotFoundException;
import com.salesorder.exception.DuplicateSalesOrderIdException;
import com.salesorder.model.OrderDetail;
import com.salesorder.model.SalesOrder;
import com.salesorder.repository.SalesOrderRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

@Service
@Transactional
public class SalesOrderService {

    private final SalesOrderRepository salesOrderRepository;

    public SalesOrderService(SalesOrderRepository salesOrderRepository) {
        this.salesOrderRepository = salesOrderRepository;
    }

    public SalesOrderResponse createSalesOrder(SalesOrderRequest request) {
        if (salesOrderRepository.existsById(request.orderNumber())) {
            throw new DuplicateSalesOrderIdException(
                "Sales order with number " + request.orderNumber() + " already exists");
        }

        SalesOrder order = new SalesOrder();
        order.setOrderNumber(request.orderNumber());
        order.setCustomerId(request.customerId());
        order.setCustomerName(request.customerName());
        order.setOrderDate(request.orderDate());
        order.setStatus(request.status());
        order.setTotalAmount(request.totalAmount());

        if (request.orderDetails() != null) {
            for (OrderDetailRequest detailReq : request.orderDetails()) {
                OrderDetail detail = toOrderDetail(detailReq);
                order.addOrderDetail(detail);
            }
        }

        try {
            SalesOrder saved = salesOrderRepository.save(order);
            return toResponse(saved);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicateSalesOrderIdException(
                "Sales order with number " + request.orderNumber() + " already exists");
        }
    }

    @Transactional(readOnly = true)
    public SalesOrderResponse getSalesOrderById(String orderNumber) {
        SalesOrder order = salesOrderRepository.findById(orderNumber)
                .orElseThrow(() -> new SalesOrderNotFoundException(
                    "Sales order with number " + orderNumber + " not found"));
        return toResponse(order);
    }

    @Transactional(readOnly = true)
    public List<SalesOrderResponse> searchSalesOrders(String customerId, String customerName, String status) {
        boolean hasAnyCriteria = (customerId != null && !customerId.isBlank())
                || (customerName != null && !customerName.isBlank())
                || (status != null && !status.isBlank());

        if (!hasAnyCriteria) {
            return salesOrderRepository.findAll().stream()
                    .map(this::toResponse)
                    .toList();
        }

        List<SalesOrder> results = null;

        if (customerId != null && !customerId.isBlank()) {
            results = new ArrayList<>(
                salesOrderRepository.findByCustomerIdContainingIgnoreCase(customerId));
        }
        if (customerName != null && !customerName.isBlank()) {
            List<SalesOrder> matched =
                salesOrderRepository.findByCustomerNameContainingIgnoreCase(customerName);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }
        if (status != null && !status.isBlank()) {
            List<SalesOrder> matched =
                salesOrderRepository.findByStatusContainingIgnoreCase(status);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }

        return results.stream().map(this::toResponse).toList();
    }

    public SalesOrderResponse updateSalesOrder(String orderNumber, SalesOrderUpdateRequest request) {
        SalesOrder order = salesOrderRepository.findById(orderNumber)
                .orElseThrow(() -> new SalesOrderNotFoundException(
                    "Sales order with number " + orderNumber + " not found"));

        order.setCustomerId(request.customerId());
        order.setCustomerName(request.customerName());
        order.setOrderDate(request.orderDate());
        order.setStatus(request.status());
        order.setTotalAmount(request.totalAmount());

        // Replace order details
        order.clearOrderDetails();
        if (request.orderDetails() != null) {
            for (OrderDetailRequest detailReq : request.orderDetails()) {
                OrderDetail detail = toOrderDetail(detailReq);
                order.addOrderDetail(detail);
            }
        }

        SalesOrder updated = salesOrderRepository.save(order);
        return toResponse(updated);
    }

    public void deleteSalesOrder(String orderNumber) {
        if (!salesOrderRepository.existsById(orderNumber)) {
            throw new SalesOrderNotFoundException(
                "Sales order with number " + orderNumber + " not found");
        }
        salesOrderRepository.deleteById(orderNumber);
    }

    private List<SalesOrder> intersect(List<SalesOrder> a, List<SalesOrder> b) {
        List<SalesOrder> result = new ArrayList<>(a);
        result.retainAll(b);
        return result;
    }

    private OrderDetail toOrderDetail(OrderDetailRequest request) {
        OrderDetail detail = new OrderDetail();
        detail.setProductId(request.productId());
        detail.setProductName(request.productName());
        detail.setQuantity(request.quantity());
        detail.setUnitPrice(request.unitPrice());
        detail.setSubtotal(request.subtotal());
        return detail;
    }

    private SalesOrderResponse toResponse(SalesOrder order) {
        List<OrderDetailResponse> detailResponses = order.getOrderDetails().stream()
                .map(detail -> new OrderDetailResponse(
                        detail.getId(),
                        detail.getProductId(),
                        detail.getProductName(),
                        detail.getQuantity(),
                        detail.getUnitPrice(),
                        detail.getSubtotal(),
                        detail.getCreatedAt(),
                        detail.getUpdatedAt()
                ))
                .toList();

        return new SalesOrderResponse(
                order.getOrderNumber(),
                order.getCustomerId(),
                order.getCustomerName(),
                order.getOrderDate(),
                order.getStatus(),
                order.getTotalAmount(),
                detailResponses,
                order.getCreatedAt(),
                order.getUpdatedAt()
        );
    }
}
