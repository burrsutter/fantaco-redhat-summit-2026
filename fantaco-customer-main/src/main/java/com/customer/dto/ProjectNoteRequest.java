package com.customer.dto;

import com.customer.model.ProjectNoteType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record ProjectNoteRequest(
    @NotBlank(message = "Note text is required")
    String noteText,

    @NotNull(message = "Note type is required")
    ProjectNoteType noteType,

    @Size(max = 100, message = "Author must not exceed 100 characters")
    String author
) {}
