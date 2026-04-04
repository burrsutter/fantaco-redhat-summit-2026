-- Sample data for Fantaco Finance API
-- Customer IDs aligned with fantaco-customer-main (CUST001-CUST011)
-- Order numbers aligned with fantaco-sales-order-main (ORD-2025-0001–ORD-2025-0007, ORD-2026-0001–ORD-2026-0006)
-- Invoice totals match sales_order.total_amount (which equals sum of order_detail subtotals)

-- ORD-2025-0001 (CUST001 - Brew & Bean Coffee Shop): $1,297.40 total → 2 invoices PAID
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-001', 'ORD-2025-0001', 'CUST001', 648.70, 'PAID', '2025-01-10 10:30:00', '2025-02-10 10:30:00', '2025-01-18 09:15:00', '2025-01-10 10:30:00'),
('INV-2025-002', 'ORD-2025-0001', 'CUST001', 648.70, 'PAID', '2025-01-10 10:35:00', '2025-02-10 10:35:00', '2025-01-22 14:30:00', '2025-01-10 10:35:00');

-- ORD-2025-0002 (CUST002 - Green Thumb Garden Center): $899.98 total → 2 invoices SENT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-003', 'ORD-2025-0002', 'CUST002', 449.99, 'SENT', '2025-01-16 14:00:00', '2025-02-16 14:00:00', NULL, '2025-01-16 14:00:00'),
('INV-2025-004', 'ORD-2025-0002', 'CUST002', 449.99, 'SENT', '2025-01-16 14:05:00', '2025-02-16 14:05:00', NULL, '2025-01-16 14:05:00');

-- ORD-2025-0003 (CUST003 - Tech Solutions IT): $7,419.79 total → 3 invoices (SENT + OVERDUE)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-005', 'ORD-2025-0003', 'CUST003', 2473.27, 'SENT', '2025-02-06 09:00:00', '2025-03-06 09:00:00', NULL, '2025-02-06 09:00:00'),
('INV-2025-006', 'ORD-2025-0003', 'CUST003', 2473.26, 'OVERDUE', '2025-02-06 09:05:00', '2025-03-06 09:05:00', NULL, '2025-02-06 09:05:00'),
('INV-2025-007', 'ORD-2025-0003', 'CUST003', 2473.26, 'SENT', '2025-02-06 09:10:00', '2025-04-06 09:10:00', NULL, '2025-02-06 09:10:00');

-- ORD-2025-0004 (CUST004 - Sweet Treats Bakery): $483.90 total → 3 invoices DRAFT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-008', 'ORD-2025-0004', 'CUST004', 161.30, 'DRAFT', '2025-02-13 11:00:00', '2025-03-13 11:00:00', NULL, '2025-02-13 11:00:00'),
('INV-2025-009', 'ORD-2025-0004', 'CUST004', 161.30, 'DRAFT', '2025-02-13 11:05:00', '2025-03-13 11:05:00', NULL, '2025-02-13 11:05:00'),
('INV-2025-010', 'ORD-2025-0004', 'CUST004', 161.30, 'DRAFT', '2025-02-13 11:10:00', '2025-03-13 11:10:00', NULL, '2025-02-13 11:10:00');

-- ORD-2025-0005 (CUST005 - Urban Fitness Studio): $599.44 total → 2 invoices CANCELLED (order was cancelled)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-011', 'ORD-2025-0005', 'CUST005', 299.72, 'CANCELLED', '2025-02-21 15:00:00', '2025-03-21 15:00:00', NULL, '2025-02-21 15:00:00'),
('INV-2025-012', 'ORD-2025-0005', 'CUST005', 299.72, 'CANCELLED', '2025-02-21 15:05:00', '2025-03-21 15:05:00', NULL, '2025-02-21 15:05:00');

-- ORD-2025-0006 (CUST006 - Creative Design Co): $999.73 total → 3 invoices (SENT + OVERDUE)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-013', 'ORD-2025-0006', 'CUST006', 333.25, 'SENT', '2025-03-08 10:00:00', '2025-04-08 10:00:00', NULL, '2025-03-08 10:00:00'),
('INV-2025-014', 'ORD-2025-0006', 'CUST006', 333.24, 'OVERDUE', '2025-03-08 10:05:00', '2025-04-08 10:05:00', NULL, '2025-03-08 10:05:00'),
('INV-2025-015', 'ORD-2025-0006', 'CUST006', 333.24, 'SENT', '2025-03-08 10:10:00', '2025-05-08 10:10:00', NULL, '2025-03-08 10:10:00');

-- ORD-2025-0007 (CUST007 - Pet Paradise Store): $424.00 total → 2 invoices PAID
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-016', 'ORD-2025-0007', 'CUST007', 212.00, 'PAID', '2025-03-20 09:30:00', '2025-04-20 09:30:00', '2025-03-28 11:00:00', '2025-03-20 09:30:00'),
('INV-2025-017', 'ORD-2025-0007', 'CUST007', 212.00, 'PAID', '2025-03-20 09:35:00', '2025-04-20 09:35:00', '2025-04-01 16:45:00', '2025-03-20 09:35:00');

-- ORD-2026-0001 (CUST008 - Local Bookshop): $324.25 total → 2 invoices SENT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-001', 'ORD-2026-0001', 'CUST008', 162.13, 'SENT', '2026-01-24 13:00:00', '2026-02-24 13:00:00', NULL, '2026-01-24 13:00:00'),
('INV-2026-002', 'ORD-2026-0001', 'CUST008', 162.12, 'SENT', '2026-01-24 13:05:00', '2026-02-24 13:05:00', NULL, '2026-01-24 13:05:00');

-- ORD-2026-0002 (CUST009 - Fresh Market Grocery): $898.40 total → 3 invoices DRAFT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-003', 'ORD-2026-0002', 'CUST009', 299.47, 'DRAFT', '2026-02-07 08:00:00', '2026-03-07 08:00:00', NULL, '2026-02-07 08:00:00'),
('INV-2026-004', 'ORD-2026-0002', 'CUST009', 299.47, 'DRAFT', '2026-02-07 08:05:00', '2026-03-07 08:05:00', NULL, '2026-02-07 08:05:00'),
('INV-2026-005', 'ORD-2026-0002', 'CUST009', 299.46, 'DRAFT', '2026-02-07 08:10:00', '2026-03-07 08:10:00', NULL, '2026-02-07 08:10:00');

-- ORD-2026-0003 (CUST010 - Handcrafted Furniture): $1,899.91 total → 3 invoices (SENT + OVERDUE)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-006', 'ORD-2026-0003', 'CUST010', 633.31, 'SENT', '2026-03-12 10:00:00', '2026-04-12 10:00:00', NULL, '2026-03-12 10:00:00'),
('INV-2026-007', 'ORD-2026-0003', 'CUST010', 633.30, 'OVERDUE', '2026-03-12 10:05:00', '2026-04-12 10:05:00', NULL, '2026-03-12 10:05:00'),
('INV-2026-008', 'ORD-2026-0003', 'CUST010', 633.30, 'SENT', '2026-03-12 10:10:00', '2026-05-12 10:10:00', NULL, '2026-03-12 10:10:00');

-- ORD-2026-0004 (CUST011 - Mind & Body Wellness Center): $3,997.11 total → 3 invoices DRAFT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-009', 'ORD-2026-0004', 'CUST011', 1332.37, 'DRAFT', '2026-03-17 09:00:00', '2026-04-17 09:00:00', NULL, '2026-03-17 09:00:00'),
('INV-2026-010', 'ORD-2026-0004', 'CUST011', 1332.37, 'DRAFT', '2026-03-17 09:05:00', '2026-04-17 09:05:00', NULL, '2026-03-17 09:05:00'),
('INV-2026-011', 'ORD-2026-0004', 'CUST011', 1332.37, 'DRAFT', '2026-03-17 09:10:00', '2026-04-17 09:10:00', NULL, '2026-03-17 09:10:00');

-- ORD-2026-0005 (CUST003 - Tech Solutions IT): $3,779.79 total → 2 invoices SENT
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-012', 'ORD-2026-0005', 'CUST003', 1889.90, 'SENT', '2026-04-10 10:00:00', '2026-05-10 10:00:00', NULL, '2026-04-10 10:00:00'),
('INV-2026-013', 'ORD-2026-0005', 'CUST003', 1889.89, 'SENT', '2026-04-10 10:05:00', '2026-05-10 10:05:00', NULL, '2026-04-10 10:05:00');

-- ORD-2026-0006 (CUST003 - Tech Solutions IT): $245,000.00 total → 3 invoices (milestone billing for Imagination Pod build)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-014', 'ORD-2026-0006', 'CUST003', 81666.67, 'SENT', '2026-03-06 14:00:00', '2026-04-06 14:00:00', NULL, '2026-03-06 14:00:00'),
('INV-2026-015', 'ORD-2026-0006', 'CUST003', 81666.67, 'SENT', '2026-03-06 14:05:00', '2026-05-06 14:05:00', NULL, '2026-03-06 14:05:00'),
('INV-2026-016', 'ORD-2026-0006', 'CUST003', 81666.66, 'DRAFT', '2026-03-06 14:10:00', '2026-06-06 14:10:00', NULL, '2026-03-06 14:10:00');

-- Additional invoices (refunds, corrections)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2025-018', 'ORD-2025-0001', 'CUST001', 129.99, 'REFUNDED', '2025-02-01 09:00:00', '2025-03-01 09:00:00', '2025-02-05 10:00:00', '2025-02-01 09:00:00'),
('INV-2025-019', 'ORD-2025-0003', 'CUST003', 75.00, 'PAID', '2025-02-25 14:00:00', '2025-03-25 14:00:00', '2025-03-01 09:30:00', '2025-02-25 14:00:00'),
('INV-2025-020', 'ORD-2025-0006', 'CUST006', 50.00, 'SENT', '2025-04-01 11:00:00', '2025-05-01 11:00:00', NULL, '2025-04-01 11:00:00'),
('INV-2025-021', 'ORD-2025-0007', 'CUST007', 25.00, 'REFUNDED', '2025-04-05 15:00:00', '2025-05-05 15:00:00', '2025-04-08 10:00:00', '2025-04-05 15:00:00'),
('INV-2026-017', 'ORD-2026-0003', 'CUST010', 199.99, 'DRAFT', '2026-03-20 09:00:00', '2026-04-20 09:00:00', NULL, '2026-03-20 09:00:00');

-- ORD-2026-0007 (CUST010 - Handcrafted Furniture): $210,500.00 total → 3 milestone invoices PAID (project completed)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-018', 'ORD-2026-0007', 'CUST010', 70166.67, 'PAID', '2026-01-17 09:00:00', '2026-02-17 09:00:00', '2026-01-25 14:30:00', '2026-01-17 09:00:00'),
('INV-2026-019', 'ORD-2026-0007', 'CUST010', 70166.67, 'PAID', '2026-02-10 09:00:00', '2026-03-10 09:00:00', '2026-02-20 10:15:00', '2026-02-10 09:00:00'),
('INV-2026-020', 'ORD-2026-0007', 'CUST010', 70166.66, 'PAID', '2026-03-05 09:00:00', '2026-04-05 09:00:00', '2026-03-12 16:00:00', '2026-03-05 09:00:00');

-- ORD-2026-0008 (CUST011 - Mind & Body Wellness Center): $135,000.00 total → 3 milestone invoices (partially paid, project in progress)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-021', 'ORD-2026-0008', 'CUST011', 45000.00, 'PAID', '2026-02-17 10:00:00', '2026-03-17 10:00:00', '2026-03-01 11:30:00', '2026-02-17 10:00:00'),
('INV-2026-022', 'ORD-2026-0008', 'CUST011', 45000.00, 'SENT', '2026-03-15 10:00:00', '2026-04-15 10:00:00', NULL, '2026-03-15 10:00:00'),
('INV-2026-023', 'ORD-2026-0008', 'CUST011', 45000.00, 'DRAFT', '2026-05-01 10:00:00', '2026-06-01 10:00:00', NULL, '2026-05-01 10:00:00');

-- ORD-2026-0009 (CUST001 - Brew & Bean Coffee Shop): $162,000.00 total → 3 invoices DRAFT (project just approved, billing not started)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-024', 'ORD-2026-0009', 'CUST001', 54000.00, 'DRAFT', '2026-04-22 11:00:00', '2026-05-22 11:00:00', NULL, '2026-04-22 11:00:00'),
('INV-2026-025', 'ORD-2026-0009', 'CUST001', 54000.00, 'DRAFT', '2026-06-01 11:00:00', '2026-07-01 11:00:00', NULL, '2026-06-01 11:00:00'),
('INV-2026-026', 'ORD-2026-0009', 'CUST001', 54000.00, 'DRAFT', '2026-07-15 11:00:00', '2026-08-15 11:00:00', NULL, '2026-07-15 11:00:00');

-- ORD-2026-0010 (CUST006 - Creative Design Co): $175,000.00 total → 3 invoices DRAFT (project still in proposal stage)
INSERT INTO invoices (invoice_number, order_number, customer_id, amount, status, invoice_date, due_date, paid_date, created_at) VALUES
('INV-2026-027', 'ORD-2026-0010', 'CUST006', 58333.34, 'DRAFT', '2026-03-27 14:00:00', '2026-04-27 14:00:00', NULL, '2026-03-27 14:00:00'),
('INV-2026-028', 'ORD-2026-0010', 'CUST006', 58333.33, 'DRAFT', '2026-08-15 14:00:00', '2026-09-15 14:00:00', NULL, '2026-08-15 14:00:00'),
('INV-2026-029', 'ORD-2026-0010', 'CUST006', 58333.33, 'DRAFT', '2026-09-20 14:00:00', '2026-10-20 14:00:00', NULL, '2026-09-20 14:00:00');

-- Insert sample disputes
INSERT INTO disputes (dispute_number, order_number, customer_id, dispute_type, status, description, reason, dispute_date, resolved_date, created_at) VALUES
('DISP-001', 'ORD-2025-0003', 'CUST003', 'BILLING_ERROR', 'RESOLVED', 'Incorrect tax calculation on invoice INV-2025-006', 'Tax rate was applied incorrectly for state', '2025-02-25 10:00:00', '2025-03-05 14:30:00', '2025-02-25 10:00:00'),
('DISP-002', 'ORD-2025-0006', 'CUST006', 'DUPLICATE_CHARGE', 'OPEN', 'Charged twice for invoice INV-2025-014', 'Payment processor error caused duplicate charge', '2025-03-15 14:30:00', NULL, '2025-03-15 14:30:00'),
('DISP-003', 'ORD-2026-0003', 'CUST010', 'PRODUCT_NOT_RECEIVED', 'IN_PROGRESS', 'Partial shipment missing from order', 'Package tracking shows delivered but items missing', '2026-03-18 16:45:00', NULL, '2026-03-18 16:45:00'),
('DISP-004', 'ORD-2025-0005', 'CUST005', 'UNAUTHORIZED_CHARGE', 'CLOSED', 'Charge appeared after order was cancelled', 'Cancellation was not processed before billing cycle', '2025-03-01 09:00:00', '2025-03-15 11:00:00', '2025-03-01 09:00:00'),
('DISP-005', 'ORD-2026-0002', 'CUST009', 'DEFECTIVE_PRODUCT', 'OPEN', 'Received damaged desk organizers from order', 'Two Imagination Pod Triage Vaults arrived with cracked compartments and do not sit level', '2026-02-15 10:30:00', NULL, '2026-02-15 10:30:00');

-- Insert sample receipts
INSERT INTO receipts (receipt_number, order_number, customer_id, status, file_path, file_name, file_size, mime_type, receipt_date, created_at) VALUES
('RCPT-001', 'ORD-2025-0001', 'CUST001', 'FOUND', '/receipts/2025/01/rcpt-001.pdf', 'receipt-ORD-2025-0001.pdf', 245760, 'application/pdf', '2025-01-18 09:20:00', '2025-01-18 09:20:00'),
('RCPT-002', 'ORD-2025-0002', 'CUST002', 'PENDING', NULL, NULL, NULL, NULL, '2025-01-16 14:10:00', '2025-01-16 14:10:00'),
('RCPT-003', 'ORD-2025-0003', 'CUST003', 'FOUND', '/receipts/2025/02/rcpt-003.pdf', 'receipt-ORD-2025-0003.pdf', 198432, 'application/pdf', '2025-02-06 09:15:00', '2025-02-06 09:15:00'),
('RCPT-004', 'ORD-2025-0004', 'CUST004', 'PENDING', NULL, NULL, NULL, NULL, '2025-02-13 11:15:00', '2025-02-13 11:15:00'),
('RCPT-005', 'ORD-2025-0005', 'CUST005', 'CANCELLED', NULL, NULL, NULL, NULL, '2025-02-21 15:10:00', '2025-02-21 15:10:00'),
('RCPT-006', 'ORD-2025-0006', 'CUST006', 'LOST', NULL, NULL, NULL, NULL, '2025-03-08 10:15:00', '2025-03-08 10:15:00'),
('RCPT-007', 'ORD-2025-0007', 'CUST007', 'FOUND', '/receipts/2025/03/rcpt-007.pdf', 'receipt-ORD-2025-0007.pdf', 312456, 'application/pdf', '2025-03-28 11:05:00', '2025-03-28 11:05:00'),
('RCPT-008', 'ORD-2026-0001', 'CUST008', 'PENDING', NULL, NULL, NULL, NULL, '2026-01-24 13:10:00', '2026-01-24 13:10:00'),
('RCPT-009', 'ORD-2026-0002', 'CUST009', 'LOST', NULL, NULL, NULL, NULL, '2026-02-07 08:15:00', '2026-02-07 08:15:00'),
('RCPT-010', 'ORD-2026-0003', 'CUST010', 'REGENERATED', '/receipts/2026/03/rcpt-010-regen.pdf', 'receipt-ORD-2026-0003-regen.pdf', 287654, 'application/pdf', '2026-03-12 10:15:00', '2026-03-12 10:15:00'),
('RCPT-011', 'ORD-2026-0004', 'CUST011', 'PENDING', NULL, NULL, NULL, NULL, '2026-03-17 09:15:00', '2026-03-17 09:15:00'),
('RCPT-012', 'ORD-2026-0005', 'CUST003', 'PENDING', NULL, NULL, NULL, NULL, '2026-04-10 10:15:00', '2026-04-10 10:15:00'),
('RCPT-013', 'ORD-2026-0006', 'CUST003', 'FOUND', '/receipts/2026/03/rcpt-013.pdf', 'receipt-ORD-2026-0006.pdf', 524288, 'application/pdf', '2026-03-06 14:15:00', '2026-03-06 14:15:00'),
('RCPT-014', 'ORD-2026-0007', 'CUST010', 'FOUND', '/receipts/2026/03/rcpt-014.pdf', 'receipt-ORD-2026-0007.pdf', 498712, 'application/pdf', '2026-03-12 16:15:00', '2026-03-12 16:15:00'),
('RCPT-015', 'ORD-2026-0008', 'CUST011', 'PENDING', NULL, NULL, NULL, NULL, '2026-02-17 10:15:00', '2026-02-17 10:15:00'),
('RCPT-016', 'ORD-2026-0009', 'CUST001', 'PENDING', NULL, NULL, NULL, NULL, '2026-04-22 11:15:00', '2026-04-22 11:15:00'),
('RCPT-017', 'ORD-2026-0010', 'CUST006', 'PENDING', NULL, NULL, NULL, NULL, '2026-03-27 14:15:00', '2026-03-27 14:15:00');
