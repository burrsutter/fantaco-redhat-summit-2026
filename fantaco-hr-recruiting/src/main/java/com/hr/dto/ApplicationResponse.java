package com.hr.dto;

import java.time.LocalDateTime;

public record ApplicationResponse(
    String applicationId,
    String jobId,
    String applicantName,
    String applicantEmail,
    String resumeData,
    String status,
    LocalDateTime submittedAt,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
