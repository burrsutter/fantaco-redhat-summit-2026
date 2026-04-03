package com.customer.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

public record MilestoneRequest(
    @NotBlank(message = "Milestone name is required")
    @Size(max = 150, message = "Milestone name must not exceed 150 characters")
    String name,

    LocalDate dueDate,

    @Size(max = 1000, message = "Notes must not exceed 1000 characters")
    String notes,

    @NotNull(message = "Sort order is required")
    Integer sortOrder
) {}
