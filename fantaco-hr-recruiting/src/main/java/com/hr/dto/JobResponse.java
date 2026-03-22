package com.hr.dto;

import java.time.LocalDateTime;

public record JobResponse(
    String jobId,
    String title,
    String description,
    LocalDateTime postedAt,
    String status,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
