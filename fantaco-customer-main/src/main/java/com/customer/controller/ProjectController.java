package com.customer.controller;

import com.customer.dto.ProjectDetailResponse;
import com.customer.dto.ProjectRequest;
import com.customer.dto.ProjectResponse;
import com.customer.dto.ProjectUpdateRequest;
import com.customer.model.PodTheme;
import com.customer.model.ProjectStatus;
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
@RequestMapping("/api/customers/{customerId}/projects")
@Tag(name = "Projects", description = "Imagination Pod project management operations")
public class ProjectController {

    private static final Logger logger = LoggerFactory.getLogger(ProjectController.class);

    private final ProjectService projectService;

    public ProjectController(ProjectService projectService) {
        this.projectService = projectService;
    }

    @PostMapping
    @Operation(summary = "Create a new project", description = "Creates a new Imagination Pod project for a customer")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Project created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<ProjectResponse> createProject(
            @PathVariable String customerId,
            @Valid @RequestBody ProjectRequest request) {
        logger.info("createProject called for customer: {}", customerId);
        ProjectResponse response = projectService.createProject(customerId, request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.id())
                .toUri();

        logger.info("createProject returning project id: {}", response.id());
        return ResponseEntity.created(location).body(response);
    }

    @GetMapping
    @Operation(summary = "List projects", description = "Lists all projects for a customer with optional status and theme filters")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "List of projects"),
        @ApiResponse(responseCode = "404", description = "Customer not found")
    })
    public ResponseEntity<List<ProjectResponse>> getProjects(
            @PathVariable String customerId,
            @RequestParam(required = false) ProjectStatus status,
            @RequestParam(required = false) PodTheme podTheme) {
        logger.info("getProjects called for customer: {}, status: {}, podTheme: {}", customerId, status, podTheme);
        List<ProjectResponse> projects = projectService.getProjectsByCustomerId(customerId, status, podTheme);
        logger.info("getProjects returning {} projects", projects.size());
        return ResponseEntity.ok(projects);
    }

    @GetMapping("/{projectId}")
    @Operation(summary = "Get project detail", description = "Retrieves a project with milestones and notes")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Project detail found"),
        @ApiResponse(responseCode = "404", description = "Customer or project not found")
    })
    public ResponseEntity<ProjectDetailResponse> getProjectDetail(
            @PathVariable String customerId,
            @PathVariable Long projectId) {
        logger.info("getProjectDetail called for customer: {}, project: {}", customerId, projectId);
        ProjectDetailResponse response = projectService.getProjectDetailById(customerId, projectId);
        logger.info("getProjectDetail returning project: {}", projectId);
        return ResponseEntity.ok(response);
    }

    @PutMapping("/{projectId}")
    @Operation(summary = "Update project", description = "Updates an existing project including status transitions")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Project updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer or project not found"),
        @ApiResponse(responseCode = "409", description = "Invalid status transition")
    })
    public ResponseEntity<ProjectResponse> updateProject(
            @PathVariable String customerId,
            @PathVariable Long projectId,
            @Valid @RequestBody ProjectUpdateRequest request) {
        logger.info("updateProject called for customer: {}, project: {}", customerId, projectId);
        ProjectResponse response = projectService.updateProject(customerId, projectId, request);
        logger.info("updateProject returning project: {}", projectId);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{projectId}")
    @Operation(summary = "Delete project", description = "Permanently deletes a project and all associated milestones and notes")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Project deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Customer or project not found")
    })
    public ResponseEntity<Void> deleteProject(
            @PathVariable String customerId,
            @PathVariable Long projectId) {
        logger.info("deleteProject called for customer: {}, project: {}", customerId, projectId);
        projectService.deleteProject(customerId, projectId);
        logger.info("deleteProject completed for project: {}", projectId);
        return ResponseEntity.noContent().build();
    }
}
