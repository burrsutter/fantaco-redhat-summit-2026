package com.fantaco.finance.service;

import com.fantaco.finance.dto.*;
import com.fantaco.finance.entity.*;
import com.fantaco.finance.repository.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
@Transactional
public class FinanceService {

    @Autowired
    private InvoiceRepository invoiceRepository;

    @Autowired
    private DisputeRepository disputeRepository;

    @Autowired
    private ReceiptRepository receiptRepository;

    /**
     * Get all invoices
     */
    public List<Invoice> getAllInvoices() {
        return invoiceRepository.findAll();
    }

    /**
     * Get invoice by ID
     */
    public Optional<Invoice> getInvoiceById(Long id) {
        return invoiceRepository.findById(id);
    }

    /**
     * Get invoices by customer ID
     */
    public List<Invoice> getInvoicesByCustomerId(String customerId) {
        return invoiceRepository.findByCustomerIdOrderByInvoiceDateDesc(customerId);
    }

    /**
     * Get invoices by order number
     */
    public List<Invoice> getInvoicesByOrderNumber(String orderNumber) {
        return invoiceRepository.findByOrderNumberOrderByInvoiceDateDesc(orderNumber);
    }

    /**
     * Get invoice history for a customer with optional date filtering
     */
    public List<Invoice> getInvoiceHistory(InvoiceHistoryRequest request) {
        if (request.getStartDate() != null && request.getEndDate() != null) {
            return invoiceRepository.findByCustomerIdAndInvoiceDateBetweenOrderByInvoiceDateDesc(
                    request.getCustomerId(), request.getStartDate(), request.getEndDate());
        } else if (request.getStartDate() != null) {
            return invoiceRepository.findRecentInvoicesByCustomer(
                    request.getCustomerId(), request.getStartDate());
        } else {
            List<Invoice> invoices = invoiceRepository.findByCustomerIdOrderByInvoiceDateDesc(request.getCustomerId());
            return invoices.stream()
                    .limit(request.getLimit())
                    .toList();
        }
    }

    /**
     * Start a duplicate charge dispute
     */
    public Dispute startDuplicateChargeDispute(DuplicateChargeDisputeRequest request) {
        // Check if there's already an active duplicate charge dispute for this order
        long activeDisputes = disputeRepository.countActiveDisputesByOrderAndType(
                request.getOrderNumber(), Dispute.DisputeType.DUPLICATE_CHARGE);

        if (activeDisputes > 0) {
            throw new RuntimeException("Duplicate charge dispute already exists for order: " + request.getOrderNumber());
        }

        // Create new dispute
        String disputeNumber = "DISP-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        Dispute dispute = new Dispute(
                disputeNumber,
                request.getOrderNumber(),
                request.getCustomerId(),
                Dispute.DisputeType.DUPLICATE_CHARGE,
                Dispute.DisputeStatus.OPEN
        );

        dispute.setDescription(request.getDescription());
        dispute.setReason(request.getReason());

        return disputeRepository.save(dispute);
    }

    /**
     * Find lost receipt for an order
     */
    public Receipt findLostReceipt(FindLostReceiptRequest request) {
        // Check if there's already a lost receipt for this order
        List<Receipt> existingLostReceipts = receiptRepository.findLostReceiptsByOrder(request.getOrderNumber());
        if (!existingLostReceipts.isEmpty()) {
            return existingLostReceipts.get(0);
        }

        // Create new lost receipt record
        String receiptNumber = "RCPT-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        Receipt receipt = new Receipt(
                receiptNumber,
                request.getOrderNumber(),
                request.getCustomerId(),
                Receipt.ReceiptStatus.LOST
        );

        return receiptRepository.save(receipt);
    }

    /**
     * Get all lost receipts for a customer
     */
    public List<Receipt> getLostReceiptsByCustomer(String customerId) {
        return receiptRepository.findLostReceiptsByCustomer(customerId);
    }

    /**
     * Get all disputes for a customer
     */
    public List<Dispute> getDisputesByCustomer(String customerId) {
        return disputeRepository.findByCustomerIdOrderByDisputeDateDesc(customerId);
    }
}
