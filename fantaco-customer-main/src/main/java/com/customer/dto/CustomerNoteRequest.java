package com.customer.dto;

import jakarta.validation.constraints.NotBlank;

public record CustomerNoteRequest(
    @NotBlank(message = "Note text is required")
    String noteText
) {}
