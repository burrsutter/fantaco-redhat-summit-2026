package com.fantaco.it.dto;

public class ListTicketsRequest {

    private String status;
    private String category;
    private String submittedBy;
    private String assignedTo;

    public ListTicketsRequest() {}

    public ListTicketsRequest(String status, String category, String submittedBy, String assignedTo) {
        this.status = status;
        this.category = category;
        this.submittedBy = submittedBy;
        this.assignedTo = assignedTo;
    }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getCategory() { return category; }
    public void setCategory(String category) { this.category = category; }

    public String getSubmittedBy() { return submittedBy; }
    public void setSubmittedBy(String submittedBy) { this.submittedBy = submittedBy; }

    public String getAssignedTo() { return assignedTo; }
    public void setAssignedTo(String assignedTo) { this.assignedTo = assignedTo; }

    @Override
    public String toString() {
        return "ListTicketsRequest{" +
                "status='" + status + '\'' +
                ", category='" + category + '\'' +
                ", submittedBy='" + submittedBy + '\'' +
                ", assignedTo='" + assignedTo + '\'' +
                '}';
    }
}
