package com.fantaco.it.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public class SubmitTicketRequest {

    @NotBlank(message = "Title is required")
    @Size(max = 200, message = "Title must not exceed 200 characters")
    private String title;

    private String description;

    @NotNull(message = "Category is required")
    private String category;

    @NotNull(message = "Priority is required")
    private String priority;

    @NotBlank(message = "Submitted by is required")
    private String submittedBy;

    @NotBlank(message = "Submitted by email is required")
    private String submittedByEmail;

    public SubmitTicketRequest() {}

    public SubmitTicketRequest(String title, String description, String category,
                               String priority, String submittedBy, String submittedByEmail) {
        this.title = title;
        this.description = description;
        this.category = category;
        this.priority = priority;
        this.submittedBy = submittedBy;
        this.submittedByEmail = submittedByEmail;
    }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getCategory() { return category; }
    public void setCategory(String category) { this.category = category; }

    public String getPriority() { return priority; }
    public void setPriority(String priority) { this.priority = priority; }

    public String getSubmittedBy() { return submittedBy; }
    public void setSubmittedBy(String submittedBy) { this.submittedBy = submittedBy; }

    public String getSubmittedByEmail() { return submittedByEmail; }
    public void setSubmittedByEmail(String submittedByEmail) { this.submittedByEmail = submittedByEmail; }

    @Override
    public String toString() {
        return "SubmitTicketRequest{" +
                "title='" + title + '\'' +
                ", category='" + category + '\'' +
                ", priority='" + priority + '\'' +
                ", submittedBy='" + submittedBy + '\'' +
                '}';
    }
}
