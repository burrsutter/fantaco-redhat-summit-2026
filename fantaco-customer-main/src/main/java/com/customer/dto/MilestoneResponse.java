package com.customer.dto;

import com.customer.model.MilestoneStatus;

import java.time.LocalDate;
import java.time.LocalDateTime;

public record MilestoneResponse(
    Long id,
    Long projectId,
    String name,
    MilestoneStatus status,
    LocalDate dueDate,
    LocalDate completedDate,
    String notes,
    Integer sortOrder,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
