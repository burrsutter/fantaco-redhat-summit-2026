package com.customer.dto;

import com.customer.model.PodTheme;
import com.customer.model.ProjectStatus;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDate;

public record ProjectUpdateRequest(
    @NotBlank(message = "Project name is required")
    @Size(max = 200, message = "Project name must not exceed 200 characters")
    String projectName,

    @Size(max = 2000, message = "Description must not exceed 2000 characters")
    String description,

    @NotNull(message = "Pod theme is required")
    PodTheme podTheme,

    @NotNull(message = "Status is required")
    ProjectStatus status,

    @Size(max = 500, message = "Site address must not exceed 500 characters")
    String siteAddress,

    LocalDate estimatedStartDate,
    LocalDate estimatedEndDate,
    LocalDate actualStartDate,
    LocalDate actualEndDate,
    BigDecimal estimatedBudget,
    BigDecimal actualCost
) {}
