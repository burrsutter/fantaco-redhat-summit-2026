-- Sample data for Fantaco Finance API
-- Customer IDs aligned with fantaco-customer-main (CUST001-CUST010)
-- Order numbers aligned with fantaco-sales-order-main (ORD-2025-0001–ORD-2025-0007, ORD-2026-0001–ORD-2026-0004; CUST001–CUST011)

-- ORD-2025-0001 (CUST001 - Brew & Bean Coffee): $1,299.98 total → 2 invoices PAID
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-001', 'ORD-2025-0001', 'CUST001', 649.99, 'PAID', '2024-01-15 10:30:00', '2024-02-15 10:30:00', '2024-01-20 09:15:00', '2024-01-15 10:30:00'),
('INV-2024-002', 'ORD-2025-0001', 'CUST001', 649.99, 'PAID', '2024-01-15 10:35:00', '2024-02-15 10:35:00', '2024-01-22 14:30:00', '2024-01-15 10:35:00');

-- ORD-2025-0002 (CUST002 - Taco Revolution): $799.98 total → 2 invoices SENT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-003', 'ORD-2025-0002', 'CUST002', 399.99, 'SENT', '2024-01-18 14:00:00', '2024-02-18 14:00:00', NULL, '2024-01-18 14:00:00'),
('INV-2024-004', 'ORD-2025-0002', 'CUST002', 399.99, 'SENT', '2024-01-18 14:05:00', '2024-02-18 14:05:00', NULL, '2024-01-18 14:05:00');

-- ORD-2025-0003 (CUST003 - Sunrise Bakery): $1,499.97 total → 3 invoices (SENT + OVERDUE)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-005', 'ORD-2025-0003', 'CUST003', 499.99, 'SENT', '2024-01-20 09:00:00', '2024-02-20 09:00:00', NULL, '2024-01-20 09:00:00'),
('INV-2024-006', 'ORD-2025-0003', 'CUST003', 499.99, 'OVERDUE', '2024-01-20 09:05:00', '2024-02-20 09:05:00', NULL, '2024-01-20 09:05:00'),
('INV-2024-007', 'ORD-2025-0003', 'CUST003', 499.99, 'SENT', '2024-01-20 09:10:00', '2024-03-20 09:10:00', NULL, '2024-01-20 09:10:00');

-- ORD-2025-0004 (CUST004 - Mountain View Diner): $449.97 total → 3 invoices DRAFT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-008', 'ORD-2025-0004', 'CUST004', 149.99, 'DRAFT', '2024-01-22 11:00:00', '2024-02-22 11:00:00', NULL, '2024-01-22 11:00:00'),
('INV-2024-009', 'ORD-2025-0004', 'CUST004', 149.99, 'DRAFT', '2024-01-22 11:05:00', '2024-02-22 11:05:00', NULL, '2024-01-22 11:05:00'),
('INV-2024-010', 'ORD-2025-0004', 'CUST004', 149.99, 'DRAFT', '2024-01-22 11:10:00', '2024-02-22 11:10:00', NULL, '2024-01-22 11:10:00');

-- ORD-2025-0005 (CUST005 - Coastal Cantina): $599.98 total → 2 invoices CANCELLED
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-011', 'ORD-2025-0005', 'CUST005', 299.99, 'CANCELLED', '2024-01-25 15:00:00', '2024-02-25 15:00:00', NULL, '2024-01-25 15:00:00'),
('INV-2024-012', 'ORD-2025-0005', 'CUST005', 299.99, 'CANCELLED', '2024-01-25 15:05:00', '2024-02-25 15:05:00', NULL, '2024-01-25 15:05:00');

-- ORD-2025-0006 (CUST006 - Urban Eats Kitchen): $999.97 total → 3 invoices (SENT + OVERDUE)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-013', 'ORD-2025-0006', 'CUST006', 333.33, 'SENT', '2024-02-01 10:00:00', '2024-03-01 10:00:00', NULL, '2024-02-01 10:00:00'),
('INV-2024-014', 'ORD-2025-0006', 'CUST006', 333.32, 'OVERDUE', '2024-02-01 10:05:00', '2024-03-01 10:05:00', NULL, '2024-02-01 10:05:00'),
('INV-2024-015', 'ORD-2025-0006', 'CUST006', 333.32, 'SENT', '2024-02-01 10:10:00', '2024-04-01 10:10:00', NULL, '2024-02-01 10:10:00');

-- ORD-2025-0007 (CUST007 - Golden Fork Bistro): $399.98 total → 2 invoices PAID
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-016', 'ORD-2025-0007', 'CUST007', 199.99, 'PAID', '2024-02-05 09:30:00', '2024-03-05 09:30:00', '2024-02-10 11:00:00', '2024-02-05 09:30:00'),
('INV-2024-017', 'ORD-2025-0007', 'CUST007', 199.99, 'PAID', '2024-02-05 09:35:00', '2024-03-05 09:35:00', '2024-02-12 16:45:00', '2024-02-05 09:35:00');

-- ORD-2026-0001 (CUST008 - Pepper & Sage Grill): $299.97 total → 2 invoices SENT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-018', 'ORD-2026-0001', 'CUST008', 149.99, 'SENT', '2024-02-10 13:00:00', '2024-03-10 13:00:00', NULL, '2024-02-10 13:00:00'),
('INV-2024-019', 'ORD-2026-0001', 'CUST008', 149.98, 'SENT', '2024-02-10 13:05:00', '2024-03-10 13:05:00', NULL, '2024-02-10 13:05:00');

-- ORD-2026-0002 (CUST009 - Fiesta Fresh Market): $899.98 total → 3 invoices DRAFT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-020', 'ORD-2026-0002', 'CUST009', 299.99, 'DRAFT', '2024-02-15 08:00:00', '2024-03-15 08:00:00', NULL, '2024-02-15 08:00:00'),
('INV-2024-021', 'ORD-2026-0002', 'CUST009', 300.00, 'DRAFT', '2024-02-15 08:05:00', '2024-03-15 08:05:00', NULL, '2024-02-15 08:05:00'),
('INV-2024-022', 'ORD-2026-0002', 'CUST009', 299.99, 'DRAFT', '2024-02-15 08:10:00', '2024-03-15 08:10:00', NULL, '2024-02-15 08:10:00');

-- ORD-2026-0003 (CUST010 - The Rustic Plate): $1,999.97 total → 3 invoices (SENT + OVERDUE)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-023', 'ORD-2026-0003', 'CUST010', 666.66, 'SENT', '2024-02-20 10:00:00', '2024-03-20 10:00:00', NULL, '2024-02-20 10:00:00'),
('INV-2024-024', 'ORD-2026-0003', 'CUST010', 666.66, 'OVERDUE', '2024-02-20 10:05:00', '2024-03-20 10:05:00', NULL, '2024-02-20 10:05:00'),
('INV-2024-025', 'ORD-2026-0003', 'CUST010', 666.65, 'SENT', '2024-02-20 10:10:00', '2024-04-20 10:10:00', NULL, '2024-02-20 10:10:00');

-- Additional invoices (refunds, corrections)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2024-026', 'ORD-2025-0001', 'CUST001', 129.99, 'REFUNDED', '2024-02-01 09:00:00', '2024-03-01 09:00:00', '2024-02-05 10:00:00', '2024-02-01 09:00:00'),
('INV-2024-027', 'ORD-2025-0003', 'CUST003', 75.00, 'PAID', '2024-02-25 14:00:00', '2024-03-25 14:00:00', '2024-03-01 09:30:00', '2024-02-25 14:00:00'),
('INV-2024-028', 'ORD-2025-0006', 'CUST006', 50.00, 'SENT', '2024-03-01 11:00:00', '2024-04-01 11:00:00', NULL, '2024-03-01 11:00:00'),
('INV-2024-029', 'ORD-2025-0007', 'CUST007', 25.00, 'REFUNDED', '2024-03-05 15:00:00', '2024-04-05 15:00:00', '2024-03-08 10:00:00', '2024-03-05 15:00:00'),
('INV-2024-030', 'ORD-2026-0003', 'CUST010', 199.99, 'DRAFT', '2024-03-10 09:00:00', '2024-04-10 09:00:00', NULL, '2024-03-10 09:00:00');

-- Insert sample disputes
INSERT INTO disputes (dispute_number, order_number, customer_id, dispute_type, status, description, reason, dispute_date, resolved_date, created_at) VALUES
('DISP-001', 'ORD-2025-0003', 'CUST003', 'BILLING_ERROR', 'RESOLVED', 'Incorrect tax calculation on invoice INV-2024-006', 'Tax rate was applied incorrectly for state', '2024-02-25 10:00:00', '2024-03-05 14:30:00', '2024-02-25 10:00:00'),
('DISP-002', 'ORD-2025-0006', 'CUST006', 'DUPLICATE_CHARGE', 'OPEN', 'Charged twice for invoice INV-2024-014', 'Payment processor error caused duplicate charge', '2024-03-05 14:30:00', NULL, '2024-03-05 14:30:00'),
('DISP-003', 'ORD-2026-0003', 'CUST010', 'PRODUCT_NOT_RECEIVED', 'IN_PROGRESS', 'Partial shipment missing from order', 'Package tracking shows delivered but items missing', '2024-03-08 16:45:00', NULL, '2024-03-08 16:45:00'),
('DISP-004', 'ORD-2025-0005', 'CUST005', 'UNAUTHORIZED_CHARGE', 'CLOSED', 'Charge appeared after order was cancelled', 'Cancellation was not processed before billing cycle', '2024-02-01 09:00:00', '2024-02-15 11:00:00', '2024-02-01 09:00:00'),
('DISP-005', 'ORD-2026-0002', 'CUST009', 'DEFECTIVE_PRODUCT', 'OPEN', 'Received damaged commercial taco press', 'Equipment arrived with visible dents and does not function', '2024-03-10 10:30:00', NULL, '2024-03-10 10:30:00');

-- Insert sample receipts
INSERT INTO receipts (receipt_number, order_number, customer_id, status, file_path, file_name, file_size, mime_type, receipt_date, created_at) VALUES
('RCPT-001', 'ORD-2025-0001', 'CUST001', 'FOUND', '/receipts/2024/01/rcpt-001.pdf', 'receipt-ORD-2025-0001.pdf', 245760, 'application/pdf', '2024-01-20 09:20:00', '2024-01-20 09:20:00'),
('RCPT-002', 'ORD-2025-0002', 'CUST002', 'PENDING', NULL, NULL, NULL, NULL, '2024-01-18 14:10:00', '2024-01-18 14:10:00'),
('RCPT-003', 'ORD-2025-0003', 'CUST003', 'FOUND', '/receipts/2024/01/rcpt-003.pdf', 'receipt-ORD-2025-0003.pdf', 198432, 'application/pdf', '2024-01-20 09:15:00', '2024-01-20 09:15:00'),
('RCPT-004', 'ORD-2025-0004', 'CUST004', 'PENDING', NULL, NULL, NULL, NULL, '2024-01-22 11:15:00', '2024-01-22 11:15:00'),
('RCPT-005', 'ORD-2025-0005', 'CUST005', 'CANCELLED', NULL, NULL, NULL, NULL, '2024-01-25 15:10:00', '2024-01-25 15:10:00'),
('RCPT-006', 'ORD-2025-0006', 'CUST006', 'LOST', NULL, NULL, NULL, NULL, '2024-02-01 10:15:00', '2024-02-01 10:15:00'),
('RCPT-007', 'ORD-2025-0007', 'CUST007', 'FOUND', '/receipts/2024/02/rcpt-007.pdf', 'receipt-ORD-2025-0007.pdf', 312456, 'application/pdf', '2024-02-10 11:05:00', '2024-02-10 11:05:00'),
('RCPT-008', 'ORD-2026-0001', 'CUST008', 'PENDING', NULL, NULL, NULL, NULL, '2024-02-10 13:10:00', '2024-02-10 13:10:00'),
('RCPT-009', 'ORD-2026-0002', 'CUST009', 'LOST', NULL, NULL, NULL, NULL, '2024-02-15 08:15:00', '2024-02-15 08:15:00'),
('RCPT-010', 'ORD-2026-0003', 'CUST010', 'REGENERATED', '/receipts/2024/02/rcpt-010-regen.pdf', 'receipt-ORD-2026-0003-regen.pdf', 287654, 'application/pdf', '2024-02-20 10:15:00', '2024-02-20 10:15:00');
