-- FantaCo HR - Seed Data
-- Jobs: 3 open, 2 closed/filled for variety
-- Applications: spread across jobs

-- Jobs
INSERT INTO job (job_id, title, description, posted_at, status, created_at, updated_at) VALUES
('job-001', 'Senior Backend Engineer', 'We are seeking an experienced backend engineer to join our team. Responsibilities include designing and implementing scalable APIs, working with databases, and mentoring junior developers. Requirements: 5+ years Python experience, FastAPI or similar frameworks, SQL databases, REST API design, microservices architecture.', '2025-10-01 09:00:00', 'OPEN', NOW(), NOW());

INSERT INTO job (job_id, title, description, posted_at, status, created_at, updated_at) VALUES
('job-002', 'Frontend Developer', 'Join our frontend team to build modern web applications. You will work with React, TypeScript, and modern CSS frameworks to create responsive, accessible user interfaces. Requirements: 3+ years JavaScript/TypeScript, React or Vue.js, responsive design, accessibility standards (WCAG).', '2025-10-05 10:00:00', 'OPEN', NOW(), NOW());

INSERT INTO job (job_id, title, description, posted_at, status, created_at, updated_at) VALUES
('job-003', 'DevOps Engineer', 'Help us build and maintain cloud infrastructure. Responsibilities include managing Kubernetes clusters, CI/CD pipelines, monitoring and alerting systems, and infrastructure as code. Requirements: 4+ years DevOps experience, Kubernetes, AWS/GCP, Terraform, Docker, GitOps workflows.', '2025-09-15 14:00:00', 'FILLED', NOW(), NOW());

INSERT INTO job (job_id, title, description, posted_at, status, created_at, updated_at) VALUES
('job-004', 'Data Scientist', 'We are looking for a data scientist to help us extract insights from our product and customer data. You will build predictive models, create dashboards, and work closely with product and engineering teams. Requirements: MS in Statistics/CS, Python, SQL, scikit-learn or TensorFlow, data visualization.', '2025-11-01 08:30:00', 'OPEN', NOW(), NOW());

INSERT INTO job (job_id, title, description, posted_at, status, created_at, updated_at) VALUES
('job-005', 'QA Automation Engineer', 'Join our quality assurance team to build and maintain automated testing frameworks. Responsibilities include writing end-to-end tests, API tests, and performance tests. Requirements: 3+ years QA experience, Selenium or Playwright, CI/CD integration, Python or Java.', '2025-08-20 11:00:00', 'CLOSED', NOW(), NOW());

-- Applications
INSERT INTO application (application_id, job_id, applicant_name, applicant_email, resume_data, status, submitted_at, created_at, updated_at) VALUES
('app-001', 'job-001', 'Alice Johnson', 'alice.johnson@example.com', 'Experienced backend engineer with 5 years of Python development. Proficient in FastAPI, Django, PostgreSQL, and microservices architecture. Previously worked at TechCorp building scalable APIs serving 1M+ requests/day.', 'UNDER_REVIEW', '2025-10-02 11:30:00', NOW(), NOW());

INSERT INTO application (application_id, job_id, applicant_name, applicant_email, resume_data, status, submitted_at, created_at, updated_at) VALUES
('app-002', 'job-001', 'Bob Martinez', 'bob.martinez@example.com', 'Full-stack developer transitioning to backend focus. 4 years experience with Node.js and Python. Built REST APIs for e-commerce platform handling 500K daily transactions. Strong SQL and NoSQL database skills.', 'SUBMITTED', '2025-10-03 14:15:00', NOW(), NOW());

INSERT INTO application (application_id, job_id, applicant_name, applicant_email, resume_data, status, submitted_at, created_at, updated_at) VALUES
('app-003', 'job-002', 'Carol Chen', 'carol.chen@example.com', 'Frontend developer with 4 years React experience. Built component libraries used by 50+ developers. Strong TypeScript skills, passionate about accessibility and responsive design. Portfolio includes 3 production PWAs.', 'INTERVIEW_SCHEDULED', '2025-10-06 09:45:00', NOW(), NOW());

INSERT INTO application (application_id, job_id, applicant_name, applicant_email, resume_data, status, submitted_at, created_at, updated_at) VALUES
('app-004', 'job-002', 'David Park', 'david.park@example.com', 'Junior frontend developer with 2 years experience. Skilled in React, Vue.js, and Tailwind CSS. Recent CS graduate from State University. Completed 3 internships at web development agencies.', 'REJECTED', '2025-10-07 16:20:00', NOW(), NOW());

INSERT INTO application (application_id, job_id, applicant_name, applicant_email, resume_data, status, submitted_at, created_at, updated_at) VALUES
('app-005', 'job-003', 'Eve Williams', 'eve.williams@example.com', 'Senior DevOps engineer with 6 years experience. Expert in Kubernetes, Terraform, and AWS. Managed infrastructure for 200+ microservices. Implemented GitOps workflows reducing deployment time by 70%.', 'OFFER_EXTENDED', '2025-09-16 08:00:00', NOW(), NOW());

INSERT INTO application (application_id, job_id, applicant_name, applicant_email, resume_data, status, submitted_at, created_at, updated_at) VALUES
('app-006', 'job-004', 'Frank Liu', 'frank.liu@example.com', 'Data scientist with MS in Statistics. 3 years experience building ML models for recommendation systems. Proficient in Python, scikit-learn, TensorFlow, and Apache Spark. Published 2 papers on NLP.', 'SUBMITTED', '2025-11-02 10:00:00', NOW(), NOW());
