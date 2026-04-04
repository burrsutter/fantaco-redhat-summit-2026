package com.fantaco.it.dto;

import jakarta.validation.constraints.NotBlank;

public class AddCommentRequest {

    @NotBlank(message = "Ticket number is required")
    private String ticketNumber;

    @NotBlank(message = "Author is required")
    private String author;

    @NotBlank(message = "Comment body is required")
    private String body;

    public AddCommentRequest() {}

    public AddCommentRequest(String ticketNumber, String author, String body) {
        this.ticketNumber = ticketNumber;
        this.author = author;
        this.body = body;
    }

    public String getTicketNumber() { return ticketNumber; }
    public void setTicketNumber(String ticketNumber) { this.ticketNumber = ticketNumber; }

    public String getAuthor() { return author; }
    public void setAuthor(String author) { this.author = author; }

    public String getBody() { return body; }
    public void setBody(String body) { this.body = body; }

    @Override
    public String toString() {
        return "AddCommentRequest{ticketNumber='" + ticketNumber + "', author='" + author + "'}";
    }
}
