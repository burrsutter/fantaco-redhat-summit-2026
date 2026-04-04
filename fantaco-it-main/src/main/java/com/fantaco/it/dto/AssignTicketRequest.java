package com.fantaco.it.dto;

import jakarta.validation.constraints.NotBlank;

public class AssignTicketRequest {

    @NotBlank(message = "Ticket number is required")
    private String ticketNumber;

    @NotBlank(message = "Assigned to is required")
    private String assignedTo;

    public AssignTicketRequest() {}

    public AssignTicketRequest(String ticketNumber, String assignedTo) {
        this.ticketNumber = ticketNumber;
        this.assignedTo = assignedTo;
    }

    public String getTicketNumber() { return ticketNumber; }
    public void setTicketNumber(String ticketNumber) { this.ticketNumber = ticketNumber; }

    public String getAssignedTo() { return assignedTo; }
    public void setAssignedTo(String assignedTo) { this.assignedTo = assignedTo; }

    @Override
    public String toString() {
        return "AssignTicketRequest{ticketNumber='" + ticketNumber + "', assignedTo='" + assignedTo + "'}";
    }
}
