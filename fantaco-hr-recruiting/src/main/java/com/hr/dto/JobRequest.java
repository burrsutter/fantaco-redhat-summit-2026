package com.hr.dto;

import jakarta.validation.constraints.*;
import java.time.LocalDateTime;

public record JobRequest(
    @NotBlank(message = "Job ID is required")
    @Size(max = 50, message = "Job ID must not exceed 50 characters")
    String jobId,

    @NotBlank(message = "Title is required")
    @Size(max = 200, message = "Title must not exceed 200 characters")
    String title,

    @NotBlank(message = "Description is required")
    @Size(max = 5000, message = "Description must not exceed 5000 characters")
    String description,

    LocalDateTime postedAt,

    @NotBlank(message = "Status is required")
    @Size(max = 20, message = "Status must not exceed 20 characters")
    String status
) {}
