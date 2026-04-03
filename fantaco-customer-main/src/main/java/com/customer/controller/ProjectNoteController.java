package com.customer.controller;

import com.customer.dto.ProjectNoteRequest;
import com.customer.dto.ProjectNoteResponse;
import com.customer.service.ProjectService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/customers/{customerId}/projects/{projectId}/notes")
@Tag(name = "Project Notes", description = "Project note management operations (append-only)")
public class ProjectNoteController {

    private static final Logger logger = LoggerFactory.getLogger(ProjectNoteController.class);

    private final ProjectService projectService;

    public ProjectNoteController(ProjectService projectService) {
        this.projectService = projectService;
    }

    @PostMapping
    @Operation(summary = "Add a project note", description = "Adds a new note to a project (append-only, no updates)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Note created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer or project not found")
    })
    public ResponseEntity<ProjectNoteResponse> createProjectNote(
            @PathVariable String customerId,
            @PathVariable Long projectId,
            @Valid @RequestBody ProjectNoteRequest request) {
        logger.info("createProjectNote called for customer: {}, project: {}", customerId, projectId);
        ProjectNoteResponse response = projectService.createProjectNote(customerId, projectId, request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.id())
                .toUri();

        logger.info("createProjectNote returning note id: {}", response.id());
        return ResponseEntity.created(location).body(response);
    }

    @GetMapping
    @Operation(summary = "List project notes", description = "Lists all notes for a project ordered by creation date (newest first)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "List of project notes"),
        @ApiResponse(responseCode = "404", description = "Customer or project not found")
    })
    public ResponseEntity<List<ProjectNoteResponse>> getProjectNotes(
            @PathVariable String customerId,
            @PathVariable Long projectId) {
        logger.info("getProjectNotes called for customer: {}, project: {}", customerId, projectId);
        List<ProjectNoteResponse> notes = projectService.getProjectNotes(customerId, projectId);
        logger.info("getProjectNotes returning {} notes", notes.size());
        return ResponseEntity.ok(notes);
    }

    @DeleteMapping("/{noteId}")
    @Operation(summary = "Delete project note", description = "Permanently deletes a project note")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Note deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Customer, project, or note not found")
    })
    public ResponseEntity<Void> deleteProjectNote(
            @PathVariable String customerId,
            @PathVariable Long projectId,
            @PathVariable Long noteId) {
        logger.info("deleteProjectNote called for customer: {}, project: {}, note: {}", customerId, projectId, noteId);
        projectService.deleteProjectNote(customerId, projectId, noteId);
        logger.info("deleteProjectNote completed for note: {}", noteId);
        return ResponseEntity.noContent().build();
    }
}
