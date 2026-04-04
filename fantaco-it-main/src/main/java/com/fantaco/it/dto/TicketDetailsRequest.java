package com.fantaco.it.dto;

import jakarta.validation.constraints.NotBlank;

public class TicketDetailsRequest {

    @NotBlank(message = "Ticket number is required")
    private String ticketNumber;

    public TicketDetailsRequest() {}

    public TicketDetailsRequest(String ticketNumber) {
        this.ticketNumber = ticketNumber;
    }

    public String getTicketNumber() { return ticketNumber; }
    public void setTicketNumber(String ticketNumber) { this.ticketNumber = ticketNumber; }

    @Override
    public String toString() {
        return "TicketDetailsRequest{ticketNumber='" + ticketNumber + "'}";
    }
}
