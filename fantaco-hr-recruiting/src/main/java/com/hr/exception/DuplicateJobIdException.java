package com.hr.exception;

public class DuplicateJobIdException extends RuntimeException {
    public DuplicateJobIdException(String message) {
        super(message);
    }
}
