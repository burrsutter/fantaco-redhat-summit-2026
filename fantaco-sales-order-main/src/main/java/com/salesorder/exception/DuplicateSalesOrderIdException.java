package com.salesorder.exception;

public class DuplicateSalesOrderIdException extends RuntimeException {
    public DuplicateSalesOrderIdException(String message) {
        super(message);
    }
}
