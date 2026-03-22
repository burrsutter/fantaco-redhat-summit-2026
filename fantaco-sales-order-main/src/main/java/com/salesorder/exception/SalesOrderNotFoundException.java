package com.salesorder.exception;

public class SalesOrderNotFoundException extends RuntimeException {
    public SalesOrderNotFoundException(String message) {
        super(message);
    }
}
