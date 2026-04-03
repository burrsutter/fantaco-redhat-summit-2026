-- Sales Orders — totals match sum of order_detail subtotals; catalog-aligned line items.
-- Dates: 2025 and 2026 only; Jan–Mar broadly covered.
-- Tech Solutions IT (CUST003) arc: ORD-2025-0003 = 4th-floor bridge crew catalog outfit (Launchpad desks, lighting) ahead of pod build; ORD-2026-0006 = Imagination Pod light-construction services; ORD-2026-0005 = catalog add-on during active pod install (consoles, comms, display prep).
INSERT INTO sales_order (order_number, customer_id, customer_name, order_date, status, total_amount, created_at, updated_at) VALUES
('ORD-2025-0001', 'CUST001', 'Brew & Bean Coffee Shop', '2025-01-08 10:30:00', 'DELIVERED', 1297.40, '2025-01-08 10:30:00', '2025-01-10 15:45:00'),
('ORD-2025-0002', 'CUST002', 'Green Thumb Garden Center', '2025-01-14 14:15:00', 'PROCESSING', 899.98, '2025-01-14 14:15:00', '2025-01-14 14:15:00'),
('ORD-2025-0003', 'CUST003', 'Tech Solutions IT', '2025-02-04 09:45:00', 'SHIPPED', 7419.79, '2025-02-04 09:45:00', '2025-02-05 11:30:00'),
('ORD-2025-0004', 'CUST004', 'Sweet Treats Bakery', '2025-02-11 16:20:00', 'PENDING', 483.90, '2025-02-11 16:20:00', '2025-02-11 16:20:00'),
('ORD-2025-0005', 'CUST005', 'Urban Fitness Studio', '2025-02-19 11:10:00', 'CANCELLED', 599.44, '2025-02-19 11:10:00', '2025-02-19 13:25:00'),
('ORD-2025-0006', 'CUST006', 'Creative Design Co', '2025-03-06 13:45:00', 'PROCESSING', 999.73, '2025-03-06 13:45:00', '2025-03-06 13:45:00'),
('ORD-2025-0007', 'CUST007', 'Pet Paradise Store', '2025-03-18 09:30:00', 'DELIVERED', 424.00, '2025-03-18 09:30:00', '2025-03-20 14:20:00'),
('ORD-2026-0001', 'CUST008', 'Local Bookshop', '2026-01-22 15:20:00', 'SHIPPED', 324.25, '2026-01-22 15:20:00', '2026-01-24 10:15:00'),
('ORD-2026-0002', 'CUST009', 'Fresh Market Grocery', '2026-02-05 11:00:00', 'PENDING', 898.40, '2026-02-05 11:00:00', '2026-02-05 11:00:00'),
('ORD-2026-0003', 'CUST010', 'Handcrafted Furniture', '2026-03-10 14:30:00', 'PROCESSING', 1899.91, '2026-03-10 14:30:00', '2026-03-10 14:30:00'),
('ORD-2026-0004', 'CUST011', 'Imagination Pod Installations LLC', '2026-03-15 10:00:00', 'PROCESSING', 3997.11, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0005', 'CUST003', 'Tech Solutions IT', '2026-04-08 09:00:00', 'PROCESSING', 3779.79, '2026-04-08 09:00:00', '2026-04-08 09:00:00'),
('ORD-2026-0006', 'CUST003', 'Tech Solutions IT', '2026-03-04 14:00:00', 'PROCESSING', 245000.00, '2026-03-04 14:00:00', '2026-03-04 14:00:00');

-- Order Details (line items)
INSERT INTO order_detail (order_number, product_id, product_name, quantity, unit_price, subtotal, created_at, updated_at) VALUES
-- ORD-2025-0001: Brew & Bean Coffee Shop (Jan 2025)
('ORD-2025-0001', 'PEN-BLK-001', 'Sphinx-Approved Scribe Pen', 100, 2.99, 299.00, '2025-01-08 10:30:00', '2025-01-08 10:30:00'),
('ORD-2025-0001', 'PAPER-A4-100', 'Chronicle of Possibility A4 Ream', 50, 4.99, 249.50, '2025-01-08 10:30:00', '2025-01-08 10:30:00'),
('ORD-2025-0001', 'NOTEBOOK-A5-001', 'Adventure Allotment Field Journal', 75, 5.99, 449.25, '2025-01-08 10:30:00', '2025-01-08 10:30:00'),
('ORD-2025-0001', 'DESK-ORG-001', 'Imagination Pod Triage Vault', 10, 19.99, 199.90, '2025-01-08 10:30:00', '2025-01-08 10:30:00'),
('ORD-2025-0001', 'POSTIT-001', 'Flash Mob & Compliment Sticky Notes', 25, 3.99, 99.75, '2025-01-08 10:30:00', '2025-01-08 10:30:00'),
-- ORD-2025-0002: Green Thumb Garden Center (Jan 2025)
('ORD-2025-0002', 'DESK-ELEC-001', 'Imagination Pod Electric Standing Desk', 1, 599.99, 599.99, '2025-01-14 14:15:00', '2025-01-14 14:15:00'),
('ORD-2025-0002', 'CHAIR-PRM-001', 'Executive Chair (Scepter-Compatible Comfort)', 1, 299.99, 299.99, '2025-01-14 14:15:00', '2025-01-14 14:15:00'),
-- ORD-2025-0003: Tech Solutions IT — Interstellar Ops Center program, phase 1 catalog (7 bridge stations; Launchpad-preset desks + exec seating + smart ambient bars before pod construction)
('ORD-2025-0003', 'DESK-ELEC-001', 'Imagination Pod Electric Standing Desk', 7, 599.99, 4199.93, '2025-02-04 09:45:00', '2025-02-04 09:45:00'),
('ORD-2025-0003', 'CHAIR-PRM-001', 'Executive Chair (Scepter-Compatible Comfort)', 7, 299.99, 2099.93, '2025-02-04 09:45:00', '2025-02-04 09:45:00'),
('ORD-2025-0003', 'LIGHT-MOD-001', 'ArtisanTech Ambient Light Bar', 7, 159.99, 1119.93, '2025-02-04 09:45:00', '2025-02-04 09:45:00'),
-- ORD-2025-0004: Sweet Treats Bakery (Feb 2025)
('ORD-2025-0004', 'PEN-BLK-001', 'Sphinx-Approved Scribe Pen', 50, 2.99, 149.50, '2025-02-11 16:20:00', '2025-02-11 16:20:00'),
('ORD-2025-0004', 'PAPER-A4-100', 'Chronicle of Possibility A4 Ream', 25, 4.99, 124.75, '2025-02-11 16:20:00', '2025-02-11 16:20:00'),
('ORD-2025-0004', 'NOTEBOOK-A5-001', 'Adventure Allotment Field Journal', 35, 5.99, 209.65, '2025-02-11 16:20:00', '2025-02-11 16:20:00'),
-- ORD-2025-0005: Urban Fitness Studio (Feb 2025)
('ORD-2025-0005', 'DESK-ORG-001', 'Imagination Pod Triage Vault', 5, 19.99, 99.95, '2025-02-19 11:10:00', '2025-02-19 11:10:00'),
('ORD-2025-0005', 'CHAIR-PRM-001', 'Executive Chair (Scepter-Compatible Comfort)', 1, 299.99, 299.99, '2025-02-19 11:10:00', '2025-02-19 11:10:00'),
('ORD-2025-0005', 'POSTIT-001', 'Flash Mob & Compliment Sticky Notes', 50, 3.99, 199.50, '2025-02-19 11:10:00', '2025-02-19 11:10:00'),
-- ORD-2025-0006: Creative Design Co (Mar 2025)
('ORD-2025-0006', 'DESK-ELEC-001', 'Imagination Pod Electric Standing Desk', 1, 599.99, 599.99, '2025-03-06 13:45:00', '2025-03-06 13:45:00'),
('ORD-2025-0006', 'CHAIR-PRM-001', 'Executive Chair (Scepter-Compatible Comfort)', 1, 299.99, 299.99, '2025-03-06 13:45:00', '2025-03-06 13:45:00'),
('ORD-2025-0006', 'POSTIT-001', 'Flash Mob & Compliment Sticky Notes', 25, 3.99, 99.75, '2025-03-06 13:45:00', '2025-03-06 13:45:00'),
-- ORD-2025-0007: Pet Paradise Store (Mar 2025)
('ORD-2025-0007', 'PEN-BLK-001', 'Sphinx-Approved Scribe Pen', 50, 2.99, 149.50, '2025-03-18 09:30:00', '2025-03-18 09:30:00'),
('ORD-2025-0007', 'PAPER-A4-100', 'Chronicle of Possibility A4 Ream', 25, 4.99, 124.75, '2025-03-18 09:30:00', '2025-03-18 09:30:00'),
('ORD-2025-0007', 'NOTEBOOK-A5-001', 'Adventure Allotment Field Journal', 25, 5.99, 149.75, '2025-03-18 09:30:00', '2025-03-18 09:30:00'),
-- ORD-2026-0001: Local Bookshop (Jan 2026)
('ORD-2026-0001', 'PEN-BLK-001', 'Sphinx-Approved Scribe Pen', 25, 2.99, 74.75, '2026-01-22 15:20:00', '2026-01-22 15:20:00'),
('ORD-2026-0001', 'NOTEBOOK-A5-001', 'Adventure Allotment Field Journal', 25, 5.99, 149.75, '2026-01-22 15:20:00', '2026-01-22 15:20:00'),
('ORD-2026-0001', 'POSTIT-001', 'Flash Mob & Compliment Sticky Notes', 25, 3.99, 99.75, '2026-01-22 15:20:00', '2026-01-22 15:20:00'),
-- ORD-2026-0002: Fresh Market Grocery (Feb 2026)
('ORD-2026-0002', 'PAPER-A4-100', 'Chronicle of Possibility A4 Ream', 100, 4.99, 499.00, '2026-02-05 11:00:00', '2026-02-05 11:00:00'),
('ORD-2026-0002', 'DESK-ORG-001', 'Imagination Pod Triage Vault', 10, 19.99, 199.90, '2026-02-05 11:00:00', '2026-02-05 11:00:00'),
('ORD-2026-0002', 'POSTIT-001', 'Flash Mob & Compliment Sticky Notes', 50, 3.99, 199.50, '2026-02-05 11:00:00', '2026-02-05 11:00:00'),
-- ORD-2026-0003: Handcrafted Furniture (Mar 2026)
('ORD-2026-0003', 'DESK-ELEC-001', 'Imagination Pod Electric Standing Desk', 2, 599.99, 1199.98, '2026-03-10 14:30:00', '2026-03-10 14:30:00'),
('ORD-2026-0003', 'CHAIR-PRM-001', 'Executive Chair (Scepter-Compatible Comfort)', 2, 299.99, 599.98, '2026-03-10 14:30:00', '2026-03-10 14:30:00'),
('ORD-2026-0003', 'DESK-ORG-001', 'Imagination Pod Triage Vault', 5, 19.99, 99.95, '2026-03-10 14:30:00', '2026-03-10 14:30:00'),
-- ORD-2026-0004: one line per remaining catalog SKU (Mar 2026)
('ORD-2026-0004', 'STAPLER-001', 'BOC Wish-Ready Heavy Stapler', 1, 12.99, 12.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'SCISSORS-001', 'Ribbon & Cape Trimming Shears', 1, 8.99, 8.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'MARKER-BLK-001', 'Void-Signing Permanent Marker', 1, 1.99, 1.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'TAPE-DISP-001', 'Portal-Sealing Desktop Tape Dispenser', 1, 6.99, 6.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'HLGHT-YEL-001', 'Highlighter of Destiny (Yellow)', 1, 1.49, 1.49, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CHAIR-BAS-001', 'Synchronized Swivel Training Chair', 1, 89.99, 89.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'MAT-FLOOR-001', 'Jousting-Lane Polycarbonate Chair Mat', 1, 49.99, 49.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'KB-MECH-001', 'RetroTech Classic Mechanical Keyboard', 1, 199.99, 199.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'KEYCAP-CUT-001', 'RetroTech Cute Animal Keycap Set', 1, 49.99, 49.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'KEYCAP-RET-001', 'RetroTech Vintage Typewriter Keycap Set', 1, 89.99, 89.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'MAT-WOOL-001', 'RetroTech Artisanal Wool Desk Mat', 1, 79.99, 79.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'LAMP-RET-001', 'RetroTech Edison Desk Lamp', 1, 129.99, 129.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'MAT-LTHR-001', 'RetroTech Premium Leather Desk Mat', 1, 149.99, 149.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'STAND-WD-001', 'RetroTech Artisan Monitor Stand', 1, 89.99, 89.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'PLANT-GEO-001', 'RetroTech Geometric Succulent Set', 1, 39.99, 39.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'AUDIO-RET-001', 'RetroTech Classic Bluetooth Speaker', 1, 159.99, 159.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CABLE-ORG-001', 'RetroTech Leather Cable Organizer', 1, 44.99, 44.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'NOTE-ECO-001', 'RetroTech Heritage Notebook', 1, 49.99, 49.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CLOCK-FLP-001', 'RetroTech Mechanical Flip Clock', 1, 119.99, 119.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'LAMP-CPR-001', 'ArtisanTech Copper Task Lamp', 1, 189.99, 189.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'STAND-BMB-001', 'ArtisanTech Bamboo Monitor Riser', 1, 129.99, 129.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CLOCK-TUB-001', 'ArtisanTech Nixie Tube Clock', 1, 249.99, 249.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'DOCK-WOOD-001', 'ArtisanTech Device Dock', 1, 89.99, 89.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'MAT-CORK-001', 'ArtisanTech Cork Desk Mat', 1, 69.99, 69.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'LIGHT-MOD-001', 'ArtisanTech Ambient Light Bar', 1, 159.99, 159.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'PEN-BRS-001', 'ArtisanTech Brass Stylus Pen', 1, 79.99, 79.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CHAIR-GAM-PRO', 'ErgoGaming Pro X Series Chair', 1, 499.99, 499.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CHAIR-GAM-FT', 'ErgoGaming Footrest Pro', 1, 79.99, 79.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CHAIR-GAM-PAD', 'ErgoGaming Lumbar Support Pro', 1, 89.99, 89.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'HDPHN-ANC-001', 'RetroTech Artisan Noise-Canceling Headphones', 1, 249.99, 249.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'FOUNT-ZEN-001', 'ArtisanTech Desktop Zen Fountain', 1, 89.99, 89.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'LED-AMB-001', 'RetroTech Smart LED Ambient Strip', 1, 59.99, 59.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'DIFF-ARO-001', 'ArtisanTech Copper Aromatherapy Diffuser', 1, 79.99, 79.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'TERR-BMB-001', 'ArtisanTech Bamboo Desktop Terrarium', 1, 59.99, 59.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'PANEL-ACU-001', 'ArtisanTech Artisan Acoustic Panel Set', 1, 149.99, 149.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CUSH-VLV-001', 'Cry Closet Velvet Comfort Cushion', 1, 69.99, 69.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'NOTE-WPR-001', 'RetroTech Waterproof Adventure Notebook', 1, 34.99, 34.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'CADDY-SNK-001', 'RetroTech Walnut Snack and Beverage Caddy', 1, 54.99, 54.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
('ORD-2026-0004', 'PURIF-DSK-001', 'ArtisanTech Copper Desktop Air Purifier', 1, 129.99, 129.99, '2026-03-15 10:00:00', '2026-03-15 10:00:00'),
-- ORD-2026-0005: Tech Solutions IT — Interstellar Ops Center program, catalog during pod install (7 seats: console input, comm headsets, walnut display risers for staging holo-adjacent monitors)
('ORD-2026-0005', 'KB-MECH-001', 'RetroTech Classic Mechanical Keyboard', 7, 199.99, 1399.93, '2026-04-08 09:00:00', '2026-04-08 09:00:00'),
('ORD-2026-0005', 'HDPHN-ANC-001', 'RetroTech Artisan Noise-Canceling Headphones', 7, 249.99, 1749.93, '2026-04-08 09:00:00', '2026-04-08 09:00:00'),
('ORD-2026-0005', 'STAND-WD-001', 'RetroTech Artisan Monitor Stand', 7, 89.99, 629.93, '2026-04-08 09:00:00', '2026-04-08 09:00:00'),
-- ORD-2026-0006: Tech Solutions IT — Interstellar Ops Center light construction (Imagination Pod service SKUs; matches CRM project estimated budget)
('ORD-2026-0006', 'IPOD-SVC-BASE', 'Imagination Pod — Interstellar Ops Center (base build)', 1, 180000.00, 180000.00, '2026-03-04 14:00:00', '2026-03-04 14:00:00'),
('ORD-2026-0006', 'IPOD-SVC-HOLO', 'Imagination Pod — Premium holographic display package', 1, 35000.00, 35000.00, '2026-03-04 14:00:00', '2026-03-04 14:00:00'),
('ORD-2026-0006', 'IPOD-SVC-STAR', 'Imagination Pod — Ambient star field ceiling', 1, 20000.00, 20000.00, '2026-03-04 14:00:00', '2026-03-04 14:00:00'),
('ORD-2026-0006', 'IPOD-SVC-PREP', 'Imagination Pod — Electrical & acoustic shell prep', 1, 10000.00, 10000.00, '2026-03-04 14:00:00', '2026-03-04 14:00:00');
