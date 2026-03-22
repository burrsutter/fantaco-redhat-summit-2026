package com.hr.exception;

public class DuplicateApplicationIdException extends RuntimeException {
    public DuplicateApplicationIdException(String message) {
        super(message);
    }
}
