package com.customer.dto;

import com.customer.model.ProjectNoteType;

import java.time.LocalDateTime;

public record ProjectNoteResponse(
    Long id,
    Long projectId,
    String noteText,
    ProjectNoteType noteType,
    String author,
    LocalDateTime createdAt
) {}
