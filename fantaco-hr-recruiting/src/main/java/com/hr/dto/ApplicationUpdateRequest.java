package com.hr.dto;

import jakarta.validation.constraints.*;
import java.time.LocalDateTime;

public record ApplicationUpdateRequest(
    @NotBlank(message = "Job ID is required")
    @Size(max = 50, message = "Job ID must not exceed 50 characters")
    String jobId,

    @NotBlank(message = "Applicant name is required")
    @Size(max = 100, message = "Applicant name must not exceed 100 characters")
    String applicantName,

    @NotBlank(message = "Applicant email is required")
    @Email(message = "Applicant email must be valid")
    @Size(max = 255, message = "Applicant email must not exceed 255 characters")
    String applicantEmail,

    @NotBlank(message = "Resume data is required")
    String resumeData,

    @NotBlank(message = "Status is required")
    @Size(max = 30, message = "Status must not exceed 30 characters")
    String status,

    LocalDateTime submittedAt
) {}
