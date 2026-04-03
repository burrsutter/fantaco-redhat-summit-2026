package com.customer.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "project", indexes = {
    @Index(name = "idx_project_customer_id", columnList = "customer_id"),
    @Index(name = "idx_project_name", columnList = "project_name"),
    @Index(name = "idx_project_pod_theme", columnList = "pod_theme"),
    @Index(name = "idx_project_status", columnList = "status")
})
public class Project {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_id", nullable = false)
    @JsonIgnore
    private Customer customer;

    @Column(name = "project_name", nullable = false, length = 200)
    @NotBlank(message = "Project name is required")
    @Size(max = 200, message = "Project name must not exceed 200 characters")
    private String projectName;

    @Column(name = "description", columnDefinition = "TEXT")
    @Size(max = 2000, message = "Description must not exceed 2000 characters")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(name = "pod_theme", nullable = false, length = 30)
    private PodTheme podTheme;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private ProjectStatus status;

    @Column(name = "site_address", length = 500)
    @Size(max = 500, message = "Site address must not exceed 500 characters")
    private String siteAddress;

    @Column(name = "estimated_start_date")
    private LocalDate estimatedStartDate;

    @Column(name = "estimated_end_date")
    private LocalDate estimatedEndDate;

    @Column(name = "actual_start_date")
    private LocalDate actualStartDate;

    @Column(name = "actual_end_date")
    private LocalDate actualEndDate;

    @Column(name = "estimated_budget", precision = 12, scale = 2)
    private BigDecimal estimatedBudget;

    @Column(name = "actual_cost", precision = 12, scale = 2)
    private BigDecimal actualCost;

    @OneToMany(mappedBy = "project", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    private List<ProjectMilestone> milestones = new ArrayList<>();

    @OneToMany(mappedBy = "project", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    private List<ProjectNote> projectNotes = new ArrayList<>();

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    public Project() {
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Customer getCustomer() {
        return customer;
    }

    public void setCustomer(Customer customer) {
        this.customer = customer;
    }

    public String getProjectName() {
        return projectName;
    }

    public void setProjectName(String projectName) {
        this.projectName = projectName;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public PodTheme getPodTheme() {
        return podTheme;
    }

    public void setPodTheme(PodTheme podTheme) {
        this.podTheme = podTheme;
    }

    public ProjectStatus getStatus() {
        return status;
    }

    public void setStatus(ProjectStatus status) {
        this.status = status;
    }

    public String getSiteAddress() {
        return siteAddress;
    }

    public void setSiteAddress(String siteAddress) {
        this.siteAddress = siteAddress;
    }

    public LocalDate getEstimatedStartDate() {
        return estimatedStartDate;
    }

    public void setEstimatedStartDate(LocalDate estimatedStartDate) {
        this.estimatedStartDate = estimatedStartDate;
    }

    public LocalDate getEstimatedEndDate() {
        return estimatedEndDate;
    }

    public void setEstimatedEndDate(LocalDate estimatedEndDate) {
        this.estimatedEndDate = estimatedEndDate;
    }

    public LocalDate getActualStartDate() {
        return actualStartDate;
    }

    public void setActualStartDate(LocalDate actualStartDate) {
        this.actualStartDate = actualStartDate;
    }

    public LocalDate getActualEndDate() {
        return actualEndDate;
    }

    public void setActualEndDate(LocalDate actualEndDate) {
        this.actualEndDate = actualEndDate;
    }

    public BigDecimal getEstimatedBudget() {
        return estimatedBudget;
    }

    public void setEstimatedBudget(BigDecimal estimatedBudget) {
        this.estimatedBudget = estimatedBudget;
    }

    public BigDecimal getActualCost() {
        return actualCost;
    }

    public void setActualCost(BigDecimal actualCost) {
        this.actualCost = actualCost;
    }

    public List<ProjectMilestone> getMilestones() {
        return milestones;
    }

    public void addMilestone(ProjectMilestone milestone) {
        milestones.add(milestone);
        milestone.setProject(this);
    }

    public void removeMilestone(ProjectMilestone milestone) {
        milestones.remove(milestone);
        milestone.setProject(null);
    }

    public List<ProjectNote> getProjectNotes() {
        return projectNotes;
    }

    public void addProjectNote(ProjectNote note) {
        projectNotes.add(note);
        note.setProject(this);
    }

    public void removeProjectNote(ProjectNote note) {
        projectNotes.remove(note);
        note.setProject(null);
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }
}
