package com.hr.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;
import java.util.Objects;

@Entity
@Table(name = "application", indexes = {
    @Index(name = "idx_app_job_id", columnList = "job_id"),
    @Index(name = "idx_app_applicant_name", columnList = "applicant_name"),
    @Index(name = "idx_app_status", columnList = "status")
})
public class Application {

    @Id
    @Column(name = "application_id", length = 50, nullable = false)
    @NotBlank(message = "Application ID is required")
    @Size(max = 50, message = "Application ID must not exceed 50 characters")
    private String applicationId;

    @Column(name = "job_id", nullable = false, length = 50)
    @NotBlank(message = "Job ID is required")
    @Size(max = 50, message = "Job ID must not exceed 50 characters")
    private String jobId;

    @Column(name = "applicant_name", nullable = false, length = 100)
    @NotBlank(message = "Applicant name is required")
    @Size(max = 100, message = "Applicant name must not exceed 100 characters")
    private String applicantName;

    @Column(name = "applicant_email", nullable = false, length = 255)
    @NotBlank(message = "Applicant email is required")
    @Email(message = "Applicant email must be valid")
    @Size(max = 255, message = "Applicant email must not exceed 255 characters")
    private String applicantEmail;

    @Column(name = "resume_data", nullable = false, columnDefinition = "TEXT")
    @NotBlank(message = "Resume data is required")
    private String resumeData;

    @Column(name = "status", nullable = false, length = 30)
    @NotBlank(message = "Status is required")
    @Size(max = 30, message = "Status must not exceed 30 characters")
    private String status;

    @Column(name = "submitted_at", nullable = false)
    private LocalDateTime submittedAt;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    public Application() {
    }

    public Application(String applicationId, String jobId) {
        this.applicationId = applicationId;
        this.jobId = jobId;
    }

    // Getters and Setters
    public String getApplicationId() {
        return applicationId;
    }

    public void setApplicationId(String applicationId) {
        this.applicationId = applicationId;
    }

    public String getJobId() {
        return jobId;
    }

    public void setJobId(String jobId) {
        this.jobId = jobId;
    }

    public String getApplicantName() {
        return applicantName;
    }

    public void setApplicantName(String applicantName) {
        this.applicantName = applicantName;
    }

    public String getApplicantEmail() {
        return applicantEmail;
    }

    public void setApplicantEmail(String applicantEmail) {
        this.applicantEmail = applicantEmail;
    }

    public String getResumeData() {
        return resumeData;
    }

    public void setResumeData(String resumeData) {
        this.resumeData = resumeData;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public LocalDateTime getSubmittedAt() {
        return submittedAt;
    }

    public void setSubmittedAt(LocalDateTime submittedAt) {
        this.submittedAt = submittedAt;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Application that = (Application) o;
        return Objects.equals(applicationId, that.applicationId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(applicationId);
    }

    @Override
    public String toString() {
        return "Application{" +
                "applicationId='" + applicationId + '\'' +
                ", jobId='" + jobId + '\'' +
                ", applicantName='" + applicantName + '\'' +
                '}';
    }
}
