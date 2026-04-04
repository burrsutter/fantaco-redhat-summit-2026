package com.fantaco.it.dto;

import jakarta.validation.constraints.NotBlank;

public class UpdateStatusRequest {

    @NotBlank(message = "Ticket number is required")
    private String ticketNumber;

    @NotBlank(message = "Status is required")
    private String status;

    private String resolution;

    public UpdateStatusRequest() {}

    public UpdateStatusRequest(String ticketNumber, String status, String resolution) {
        this.ticketNumber = ticketNumber;
        this.status = status;
        this.resolution = resolution;
    }

    public String getTicketNumber() { return ticketNumber; }
    public void setTicketNumber(String ticketNumber) { this.ticketNumber = ticketNumber; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getResolution() { return resolution; }
    public void setResolution(String resolution) { this.resolution = resolution; }

    @Override
    public String toString() {
        return "UpdateStatusRequest{ticketNumber='" + ticketNumber + "', status='" + status + "'}";
    }
}
