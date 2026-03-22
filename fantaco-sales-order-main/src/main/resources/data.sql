-- Sales Orders
INSERT INTO sales_order (order_number, customer_id, customer_name, order_date, status, total_amount, created_at, updated_at) VALUES
('ORD-2024-0001', 'CUST001', 'Brew & Bean Coffee Shop', '2024-03-01 10:30:00', 'DELIVERED', 1299.98, '2024-03-01 10:30:00', '2024-03-03 15:45:00'),
('ORD-2024-0002', 'CUST002', 'Green Thumb Garden Center', '2024-03-02 14:15:00', 'PROCESSING', 799.98, '2024-03-02 14:15:00', '2024-03-02 14:15:00'),
('ORD-2024-0003', 'CUST003', 'Tech Solutions IT', '2024-03-03 09:45:00', 'SHIPPED', 1499.97, '2024-03-03 09:45:00', '2024-03-04 11:30:00'),
('ORD-2024-0004', 'CUST004', 'Sweet Treats Bakery', '2024-03-04 16:20:00', 'PENDING', 449.97, '2024-03-04 16:20:00', '2024-03-04 16:20:00'),
('ORD-2024-0005', 'CUST005', 'Urban Fitness Studio', '2024-03-05 11:10:00', 'CANCELLED', 599.98, '2024-03-05 11:10:00', '2024-03-05 13:25:00'),
('ORD-2024-0006', 'CUST006', 'Creative Design Co', '2024-03-06 13:45:00', 'PROCESSING', 999.97, '2024-03-06 13:45:00', '2024-03-06 13:45:00'),
('ORD-2024-0007', 'CUST007', 'Pet Paradise Store', '2024-03-07 09:30:00', 'DELIVERED', 399.98, '2024-03-07 09:30:00', '2024-03-08 14:20:00'),
('ORD-2024-0008', 'CUST008', 'Local Bookshop', '2024-03-08 15:20:00', 'SHIPPED', 299.97, '2024-03-08 15:20:00', '2024-03-09 10:15:00'),
('ORD-2024-0009', 'CUST009', 'Fresh Market Grocery', '2024-03-09 11:00:00', 'PENDING', 899.98, '2024-03-09 11:00:00', '2024-03-09 11:00:00'),
('ORD-2024-0010', 'CUST010', 'Handcrafted Furniture', '2024-03-10 14:30:00', 'PROCESSING', 1999.97, '2024-03-10 14:30:00', '2024-03-10 14:30:00');

-- Order Details (line items)
INSERT INTO order_detail (order_number, product_id, product_name, quantity, unit_price, subtotal, created_at, updated_at) VALUES
-- Order 1: Brew & Bean Coffee Shop
('ORD-2024-0001', 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 100, 2.99, 299.00, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
('ORD-2024-0001', 'PAPER-A4-100', 'Premium A4 Copy Paper', 50, 4.99, 249.50, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
('ORD-2024-0001', 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 75, 5.99, 449.25, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
('ORD-2024-0001', 'DESK-ORG-001', 'Desktop Organizer', 10, 19.99, 199.90, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
('ORD-2024-0001', 'POSTIT-001', 'Sticky Notes', 25, 3.99, 99.75, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
-- Order 2: Green Thumb Garden Center
('ORD-2024-0002', 'DESK-ELEC-001', 'Electric Standing Desk', 1, 599.99, 599.99, '2024-03-02 14:15:00', '2024-03-02 14:15:00'),
('ORD-2024-0002', 'CHAIR-PRM-001', 'Ergonomic Executive Chair', 1, 299.99, 299.99, '2024-03-02 14:15:00', '2024-03-02 14:15:00'),
-- Order 3: Tech Solutions IT
('ORD-2024-0003', 'MUG-SMART-001', 'RetroTech Smart Ceramic Mug', 5, 29.99, 149.95, '2024-03-03 09:45:00', '2024-03-03 09:45:00'),
('ORD-2024-0003', 'DESK-ELEC-001', 'Electric Standing Desk', 2, 599.99, 1199.98, '2024-03-03 09:45:00', '2024-03-03 09:45:00'),
('ORD-2024-0003', 'CHAIR-PRM-001', 'Ergonomic Executive Chair', 2, 299.99, 599.98, '2024-03-03 09:45:00', '2024-03-03 09:45:00'),
-- Order 4: Sweet Treats Bakery
('ORD-2024-0004', 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 50, 2.99, 149.50, '2024-03-04 16:20:00', '2024-03-04 16:20:00'),
('ORD-2024-0004', 'PAPER-A4-100', 'Premium A4 Copy Paper', 25, 4.99, 124.75, '2024-03-04 16:20:00', '2024-03-04 16:20:00'),
('ORD-2024-0004', 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 35, 5.99, 209.65, '2024-03-04 16:20:00', '2024-03-04 16:20:00'),
-- Order 5: Urban Fitness Studio
('ORD-2024-0005', 'DESK-ORG-001', 'Desktop Organizer', 5, 19.99, 99.95, '2024-03-05 11:10:00', '2024-03-05 11:10:00'),
('ORD-2024-0005', 'CHAIR-PRM-001', 'Ergonomic Executive Chair', 1, 299.99, 299.99, '2024-03-05 11:10:00', '2024-03-05 11:10:00'),
('ORD-2024-0005', 'POSTIT-001', 'Sticky Notes', 50, 3.99, 199.50, '2024-03-05 11:10:00', '2024-03-05 11:10:00'),
-- Order 6: Creative Design Co
('ORD-2024-0006', 'DESK-ELEC-001', 'Electric Standing Desk', 1, 599.99, 599.99, '2024-03-06 13:45:00', '2024-03-06 13:45:00'),
('ORD-2024-0006', 'CHAIR-PRM-001', 'Ergonomic Executive Chair', 1, 299.99, 299.99, '2024-03-06 13:45:00', '2024-03-06 13:45:00'),
('ORD-2024-0006', 'POSTIT-001', 'Sticky Notes', 25, 3.99, 99.75, '2024-03-06 13:45:00', '2024-03-06 13:45:00'),
-- Order 7: Pet Paradise Store
('ORD-2024-0007', 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 50, 2.99, 149.50, '2024-03-07 09:30:00', '2024-03-07 09:30:00'),
('ORD-2024-0007', 'PAPER-A4-100', 'Premium A4 Copy Paper', 25, 4.99, 124.75, '2024-03-07 09:30:00', '2024-03-07 09:30:00'),
('ORD-2024-0007', 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 25, 5.99, 149.75, '2024-03-07 09:30:00', '2024-03-07 09:30:00'),
-- Order 8: Local Bookshop
('ORD-2024-0008', 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 25, 2.99, 74.75, '2024-03-08 15:20:00', '2024-03-08 15:20:00'),
('ORD-2024-0008', 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 25, 5.99, 149.75, '2024-03-08 15:20:00', '2024-03-08 15:20:00'),
('ORD-2024-0008', 'POSTIT-001', 'Sticky Notes', 25, 3.99, 99.75, '2024-03-08 15:20:00', '2024-03-08 15:20:00'),
-- Order 9: Fresh Market Grocery
('ORD-2024-0009', 'PAPER-A4-100', 'Premium A4 Copy Paper', 100, 4.99, 499.00, '2024-03-09 11:00:00', '2024-03-09 11:00:00'),
('ORD-2024-0009', 'DESK-ORG-001', 'Desktop Organizer', 10, 19.99, 199.90, '2024-03-09 11:00:00', '2024-03-09 11:00:00'),
('ORD-2024-0009', 'POSTIT-001', 'Sticky Notes', 50, 3.99, 199.50, '2024-03-09 11:00:00', '2024-03-09 11:00:00'),
-- Order 10: Handcrafted Furniture
('ORD-2024-0010', 'DESK-ELEC-001', 'Electric Standing Desk', 2, 599.99, 1199.98, '2024-03-10 14:30:00', '2024-03-10 14:30:00'),
('ORD-2024-0010', 'CHAIR-PRM-001', 'Ergonomic Executive Chair', 2, 299.99, 599.98, '2024-03-10 14:30:00', '2024-03-10 14:30:00'),
('ORD-2024-0010', 'DESK-ORG-001', 'Desktop Organizer', 5, 19.99, 99.95, '2024-03-10 14:30:00', '2024-03-10 14:30:00');
