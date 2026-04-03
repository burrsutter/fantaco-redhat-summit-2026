package com.customer.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "project_note")
public class ProjectNote {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "project_id", nullable = false)
    @JsonIgnore
    private Project project;

    @Column(name = "note_text", columnDefinition = "TEXT", nullable = false)
    @NotBlank(message = "Note text is required")
    private String noteText;

    @Enumerated(EnumType.STRING)
    @Column(name = "note_type", nullable = false, length = 20)
    private ProjectNoteType noteType;

    @Column(name = "author", length = 100)
    @Size(max = 100, message = "Author must not exceed 100 characters")
    private String author;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    public ProjectNote() {
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Project getProject() {
        return project;
    }

    public void setProject(Project project) {
        this.project = project;
    }

    public String getNoteText() {
        return noteText;
    }

    public void setNoteText(String noteText) {
        this.noteText = noteText;
    }

    public ProjectNoteType getNoteType() {
        return noteType;
    }

    public void setNoteType(ProjectNoteType noteType) {
        this.noteType = noteType;
    }

    public String getAuthor() {
        return author;
    }

    public void setAuthor(String author) {
        this.author = author;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }
}
