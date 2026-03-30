package com.customer.dto;

import java.time.LocalDateTime;

public record CustomerNoteResponse(
    Long id,
    String customerId,
    String noteText,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
