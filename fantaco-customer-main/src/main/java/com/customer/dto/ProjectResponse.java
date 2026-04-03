package com.customer.dto;

import com.customer.model.PodTheme;
import com.customer.model.ProjectStatus;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

public record ProjectResponse(
    Long id,
    String customerId,
    String projectName,
    String description,
    PodTheme podTheme,
    ProjectStatus status,
    String siteAddress,
    LocalDate estimatedStartDate,
    LocalDate estimatedEndDate,
    LocalDate actualStartDate,
    LocalDate actualEndDate,
    BigDecimal estimatedBudget,
    BigDecimal actualCost,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
