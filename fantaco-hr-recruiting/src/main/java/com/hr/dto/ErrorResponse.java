package com.hr.dto;

import java.time.LocalDateTime;
import java.util.List;

public record ErrorResponse(
    LocalDateTime timestamp,
    int status,
    String error,
    String message,
    List<ValidationError> errors
) {
    public record ValidationError(
        String field,
        String rejectedValue,
        String message
    ) {}
}
