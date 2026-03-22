-- Sample Sales Order Data
-- This file contains sample data for orders and order details using actual products and customers

-- Insert Orders
INSERT INTO orders (order_number, customer_id, customer_name, order_date, status, total_amount, created_at, updated_at)
VALUES 
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

-- Insert Order Details
INSERT INTO order_details (order_id, product_id, product_name, quantity, unit_price, subtotal, created_at, updated_at)
VALUES 
    -- Order 1: Brew & Bean Coffee Shop - Office supplies for their cafe
    (1, 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 100, 2.99, 299.00, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
    (1, 'PAPER-A4-100', 'Premium A4 Copy Paper', 50, 4.99, 249.50, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
    (1, 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 75, 5.99, 449.25, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
    (1, 'DESK-ORG-001', 'Desktop Organizer', 10, 19.99, 199.90, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
    (1, 'POSTIT-001', 'Sticky Notes', 25, 3.99, 99.75, '2024-03-01 10:30:00', '2024-03-01 10:30:00'),
    
    -- Order 2: Green Thumb Garden Center - Office furniture and supplies
    (2, 'DESK-ELEC-001', 'Electric Standing Desk', 1, 599.99, 599.99, '2024-03-02 14:15:00', '2024-03-02 14:15:00'),
    (2, 'CHAIR-PREM-001', 'Ergonomic Executive Chair', 1, 299.99, 299.99, '2024-03-02 14:15:00', '2024-03-02 14:15:00'),
    
    -- Order 3: Tech Solutions IT - High-end tech accessories
    (3, 'MUG-SMART-001', 'RetroTech Smart Ceramic Mug', 5, 29.99, 149.95, '2024-03-03 09:45:00', '2024-03-03 09:45:00'),
    (3, 'DESK-ELEC-001', 'Electric Standing Desk', 2, 599.99, 1199.98, '2024-03-03 09:45:00', '2024-03-03 09:45:00'),
    (3, 'CHAIR-PREM-001', 'Ergonomic Executive Chair', 2, 299.99, 599.98, '2024-03-03 09:45:00', '2024-03-03 09:45:00'),
    
    -- Order 4: Sweet Treats Bakery - Basic office supplies
    (4, 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 50, 2.99, 149.50, '2024-03-04 16:20:00', '2024-03-04 16:20:00'),
    (4, 'PAPER-A4-100', 'Premium A4 Copy Paper', 25, 4.99, 124.75, '2024-03-04 16:20:00', '2024-03-04 16:20:00'),
    (4, 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 35, 5.99, 209.65, '2024-03-04 16:20:00', '2024-03-04 16:20:00'),
    
    -- Order 5: Urban Fitness Studio - Office setup
    (5, 'DESK-ORG-001', 'Desktop Organizer', 5, 19.99, 99.95, '2024-03-05 11:10:00', '2024-03-05 11:10:00'),
    (5, 'CHAIR-PREM-001', 'Ergonomic Executive Chair', 1, 299.99, 299.99, '2024-03-05 11:10:00', '2024-03-05 11:10:00'),
    (5, 'POSTIT-001', 'Sticky Notes', 50, 3.99, 199.50, '2024-03-05 11:10:00', '2024-03-05 11:10:00'),
    
    -- Order 6: Creative Design Co - Creative workspace setup
    (6, 'DESK-ELEC-001', 'Electric Standing Desk', 1, 599.99, 599.99, '2024-03-06 13:45:00', '2024-03-06 13:45:00'),
    (6, 'CHAIR-PREM-001', 'Ergonomic Executive Chair', 1, 299.99, 299.99, '2024-03-06 13:45:00', '2024-03-06 13:45:00'),
    (6, 'POSTIT-001', 'Sticky Notes', 25, 3.99, 99.75, '2024-03-06 13:45:00', '2024-03-06 13:45:00'),
    
    -- Order 7: Pet Paradise Store - Basic supplies
    (7, 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 50, 2.99, 149.50, '2024-03-07 09:30:00', '2024-03-07 09:30:00'),
    (7, 'PAPER-A4-100', 'Premium A4 Copy Paper', 25, 4.99, 124.75, '2024-03-07 09:30:00', '2024-03-07 09:30:00'),
    (7, 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 25, 5.99, 149.75, '2024-03-07 09:30:00', '2024-03-07 09:30:00'),
    
    -- Order 8: Local Bookshop - Reading and writing supplies
    (8, 'PEN-BLK-001', 'Premium Black Ballpoint Pen', 25, 2.99, 74.75, '2024-03-08 15:20:00', '2024-03-08 15:20:00'),
    (8, 'NOTEBOOK-A5-001', 'Spiral Bound Notebook', 25, 5.99, 149.75, '2024-03-08 15:20:00', '2024-03-08 15:20:00'),
    (8, 'POSTIT-001', 'Sticky Notes', 25, 3.99, 99.75, '2024-03-08 15:20:00', '2024-03-08 15:20:00'),
    
    -- Order 9: Fresh Market Grocery - Office supplies
    (9, 'PAPER-A4-100', 'Premium A4 Copy Paper', 100, 4.99, 499.00, '2024-03-09 11:00:00', '2024-03-09 11:00:00'),
    (9, 'DESK-ORG-001', 'Desktop Organizer', 10, 19.99, 199.90, '2024-03-09 11:00:00', '2024-03-09 11:00:00'),
    (9, 'POSTIT-001', 'Sticky Notes', 50, 3.99, 199.50, '2024-03-09 11:00:00', '2024-03-09 11:00:00'),
    
    -- Order 10: Handcrafted Furniture - Premium office setup
    (10, 'DESK-ELEC-001', 'Electric Standing Desk', 2, 599.99, 1199.98, '2024-03-10 14:30:00', '2024-03-10 14:30:00'),
    (10, 'CHAIR-PREM-001', 'Ergonomic Executive Chair', 2, 299.99, 599.98, '2024-03-10 14:30:00', '2024-03-10 14:30:00'),
    (10, 'DESK-ORG-001', 'Desktop Organizer', 5, 19.99, 99.95, '2024-03-10 14:30:00', '2024-03-10 14:30:00'); 


-- Test to see if it JOINs correctly
SELECT 
    o.order_number,
    o.customer_name,
    o.order_date,
    o.status,
    o.total_amount,
    od.product_id,
    od.product_name,
    od.quantity,
    od.unit_price,
    od.subtotal
FROM orders o
JOIN order_details od ON o.id = od.order_id
ORDER BY o.order_number, od.product_id; 