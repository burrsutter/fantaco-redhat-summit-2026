-- Seed data for Fantaco IT Ticketing System

-- Ticket 1: Password reset (RESOLVED)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, resolved_at, created_at)
VALUES ('TKT-00001', 'Cannot log into email', 'I forgot my password and the reset link is not working. I have tried multiple times but never receive the reset email.', 'ACCESS', 'HIGH', 'RESOLVED', 'Maria Santos', 'maria.santos@fantaco.com', 'Jake Chen', '2026-03-15 14:30:00', '2026-03-14 09:15:00');

-- Ticket 2: Laptop replacement (IN_PROGRESS)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, created_at)
VALUES ('TKT-00002', 'Laptop screen flickering', 'My laptop screen has been flickering intermittently for the past week. It happens mostly when connected to the external monitor. Model: ThinkPad T14s Gen 4.', 'HARDWARE', 'MEDIUM', 'IN_PROGRESS', 'Diego Rivera', 'diego.rivera@fantaco.com', 'Sarah Kim', '2026-03-18 10:30:00');

-- Ticket 3: VPN issues (OPEN)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, created_at)
VALUES ('TKT-00003', 'VPN disconnects frequently when working from home', 'Every 15-20 minutes the VPN connection drops and I have to reconnect. This started after last weeks update. Running Windows 11 with GlobalProtect VPN client.', 'NETWORK', 'HIGH', 'OPEN', 'Priya Patel', 'priya.patel@fantaco.com', '2026-03-20 08:45:00');

-- Ticket 4: Software install request (RESOLVED)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, resolved_at, created_at)
VALUES ('TKT-00004', 'Request to install Adobe Creative Suite', 'I need Adobe Creative Suite installed for the new marketing campaign materials. Manager approval: Tom Bradley.', 'SOFTWARE', 'LOW', 'RESOLVED', 'Elena Vasquez', 'elena.vasquez@fantaco.com', 'Jake Chen', '2026-03-12 16:00:00', '2026-03-10 11:20:00');

-- Ticket 5: Printer not working (WAITING_ON_USER)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, created_at)
VALUES ('TKT-00005', '3rd floor printer jammed and offline', 'The HP LaserJet on the 3rd floor near the kitchen has been showing a paper jam error. I cleared the jam but it still shows the error.', 'HARDWARE', 'LOW', 'WAITING_ON_USER', 'Carlos Mendez', 'carlos.mendez@fantaco.com', 'Sarah Kim', '2026-03-21 13:00:00');

-- Ticket 6: New employee setup (IN_PROGRESS)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, created_at)
VALUES ('TKT-00006', 'New hire onboarding - laptop and accounts', 'New employee starting April 7: Jennifer Walsh, Sales Department. Needs laptop, email account, Salesforce access, and VPN setup.', 'ACCESS', 'HIGH', 'IN_PROGRESS', 'Tom Bradley', 'tom.bradley@fantaco.com', 'Jake Chen', '2026-03-25 09:00:00');

-- Ticket 7: Slow computer (OPEN)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, created_at)
VALUES ('TKT-00007', 'Computer extremely slow after Windows update', 'After the latest Windows update my computer takes 10+ minutes to boot and applications freeze constantly. I have 16GB RAM and an SSD so this should not be happening.', 'SOFTWARE', 'MEDIUM', 'OPEN', 'Raj Gupta', 'raj.gupta@fantaco.com', '2026-03-26 07:30:00');

-- Ticket 8: Network outage report (RESOLVED)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, resolved_at, created_at)
VALUES ('TKT-00008', 'Building B wifi completely down', 'No wifi connectivity in Building B. Multiple employees affected. Wired connections still working.', 'NETWORK', 'CRITICAL', 'RESOLVED', 'Lisa Chang', 'lisa.chang@fantaco.com', 'Mike Torres', '2026-03-16 11:45:00', '2026-03-16 08:00:00');

-- Ticket 9: Monitor request (OPEN)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, created_at)
VALUES ('TKT-00009', 'Request for second monitor', 'I work with spreadsheets and design tools simultaneously. A second monitor would significantly improve my productivity. Manager has approved.', 'HARDWARE', 'LOW', 'OPEN', 'Anna Kowalski', 'anna.kowalski@fantaco.com', '2026-03-27 14:15:00');

-- Ticket 10: Shared drive access (CLOSED)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, resolved_at, created_at)
VALUES ('TKT-00010', 'Cannot access shared drive S:', 'Getting "Access Denied" when trying to access the Finance shared drive. I was recently transferred from Marketing and need access for my new role.', 'ACCESS', 'MEDIUM', 'CLOSED', 'David Kim', 'david.kim@fantaco.com', 'Jake Chen', '2026-03-08 10:00:00', '2026-03-07 15:30:00');

-- Ticket 11: Outlook crashes (IN_PROGRESS)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, created_at)
VALUES ('TKT-00011', 'Outlook keeps crashing when opening attachments', 'Every time I try to open a PDF attachment in Outlook, the application crashes. This has been happening for 3 days. Outlook version 365, build 16.0.', 'SOFTWARE', 'HIGH', 'IN_PROGRESS', 'Sophie Martin', 'sophie.martin@fantaco.com', 'Mike Torres', '2026-03-28 11:00:00');

-- Ticket 12: Conference room AV (OPEN)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, created_at)
VALUES ('TKT-00012', 'Conference room A projector not displaying', 'The projector in Conference Room A (2nd floor) is not detecting any HDMI input. Tried multiple cables and laptops. Important client meeting tomorrow.', 'HARDWARE', 'CRITICAL', 'OPEN', 'Marcus Johnson', 'marcus.johnson@fantaco.com', '2026-03-29 16:30:00');

-- Ticket 13: Security concern (OPEN)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, created_at)
VALUES ('TKT-00013', 'Suspicious email received - possible phishing', 'I received an email claiming to be from IT asking me to verify my credentials via a link. The sender address looks suspicious: it-support@fantac0.com (with a zero). I did not click the link.', 'OTHER', 'CRITICAL', 'Nancy Rodriguez', 'nancy.rodriguez@fantaco.com', '2026-03-30 08:20:00');

-- Ticket 14: Software license (WAITING_ON_USER)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, assigned_to, created_at)
VALUES ('TKT-00014', 'IntelliJ IDEA license expired', 'My IntelliJ IDEA Ultimate license expired yesterday. I need it renewed for development work on the FantaCo microservices. License key: XXXX-XXXX-XXXX.', 'SOFTWARE', 'HIGH', 'WAITING_ON_USER', 'Alex Thompson', 'alex.thompson@fantaco.com', 'Mike Torres', '2026-03-31 09:45:00');

-- Ticket 15: Keyboard replacement (OPEN)
INSERT INTO tickets (ticket_number, title, description, category, priority, status, submitted_by, submitted_by_email, created_at)
VALUES ('TKT-00015', 'Keyboard keys sticking after coffee spill', 'Accidentally spilled coffee on my keyboard. The E, R, and T keys are sticking. Need a replacement keyboard please.', 'HARDWARE', 'LOW', 'OPEN', 'Ben O''Malley', 'ben.omalley@fantaco.com', '2026-04-01 10:00:00');

-- Comments for resolved tickets
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (1, 'Jake Chen', 'Checked the mail server logs. The reset emails were being caught by the spam filter. I have whitelisted the password reset sender and sent a new reset link.', '2026-03-14 11:00:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (1, 'Maria Santos', 'Got the reset link and was able to change my password. Thank you!', '2026-03-15 14:00:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (1, 'Jake Chen', 'Confirmed password reset successful. Closing ticket.', '2026-03-15 14:30:00');

-- Comments for laptop screen issue
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (2, 'Sarah Kim', 'Ran diagnostics on the display adapter. The issue appears to be a loose display cable. Ordering a replacement cable. ETA 2-3 business days.', '2026-03-19 10:00:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (2, 'Diego Rivera', 'Thanks for the update. I can manage with just the external monitor in the meantime.', '2026-03-19 10:30:00');

-- Comments for printer issue
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (5, 'Sarah Kim', 'The paper jam sensor needs to be cleaned. I need access to the printer during off-hours. Can you confirm when the area will be empty? Suggesting after 6 PM.', '2026-03-22 09:00:00');

-- Comments for network outage
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (8, 'Mike Torres', 'Identified the issue: a failed access point (AP-B2-03). Replacing the unit now.', '2026-03-16 09:30:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (8, 'Mike Torres', 'New access point installed and configured. All Building B wifi should be operational. Please test and confirm.', '2026-03-16 11:00:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (8, 'Lisa Chang', 'Wifi is working again. Everything looks good. Thanks for the quick fix!', '2026-03-16 11:30:00');

-- Comments for shared drive access
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (10, 'Jake Chen', 'Added David to the Finance-ReadWrite AD group. Access should be available within 15 minutes after a logoff/logon.', '2026-03-07 16:00:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (10, 'David Kim', 'I can access the shared drive now. Everything is working. Thank you!', '2026-03-08 09:00:00');

-- Comments for software install
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (4, 'Jake Chen', 'Manager approval confirmed. Installing Adobe Creative Suite 2024. Will push via SCCM to your workstation overnight.', '2026-03-11 14:00:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (4, 'Elena Vasquez', 'Adobe Creative Suite is installed and working. Thanks!', '2026-03-12 09:00:00');

-- Comments for IntelliJ license
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (14, 'Mike Torres', 'I have submitted the license renewal request to JetBrains. Need your manager to approve the PO. Can you have Tom Bradley send approval to procurement@fantaco.com?', '2026-03-31 14:00:00');

-- Comments for Outlook crashes
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (11, 'Mike Torres', 'Reproduced the issue. It appears to be related to a corrupted Outlook profile. Going to create a new profile and migrate your data. Will need 30 minutes of downtime on your machine.', '2026-03-29 09:00:00');

-- Comments for new hire onboarding
INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (6, 'Jake Chen', 'Laptop ordered: ThinkPad T14s Gen 5, 32GB RAM, 512GB SSD. Expected delivery: April 3. Email account and AD user created. Salesforce license requested from vendor.', '2026-03-26 10:00:00');

INSERT INTO ticket_comments (ticket_id, author, body, created_at)
VALUES (6, 'Jake Chen', 'Laptop received and imaged. Setting up VPN profile and installing standard software suite. Will have everything ready by April 4.', '2026-04-01 11:00:00');
