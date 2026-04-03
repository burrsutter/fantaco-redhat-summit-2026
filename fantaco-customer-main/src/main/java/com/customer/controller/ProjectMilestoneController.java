package com.customer.controller;

import com.customer.dto.MilestoneRequest;
import com.customer.dto.MilestoneResponse;
import com.customer.dto.MilestoneUpdateRequest;
import com.customer.service.ProjectMilestoneService;
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
@RequestMapping("/api/customers/{customerId}/projects/{projectId}/milestones")
@Tag(name = "Milestones", description = "Project milestone management operations")
public class ProjectMilestoneController {

    private static final Logger logger = LoggerFactory.getLogger(ProjectMilestoneController.class);

    private final ProjectMilestoneService milestoneService;

    public ProjectMilestoneController(ProjectMilestoneService milestoneService) {
        this.milestoneService = milestoneService;
    }

    @PostMapping
    @Operation(summary = "Create a milestone", description = "Creates a new milestone for a project")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Milestone created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer or project not found"),
        @ApiResponse(responseCode = "409", description = "Sort order conflict")
    })
    public ResponseEntity<MilestoneResponse> createMilestone(
            @PathVariable String customerId,
            @PathVariable Long projectId,
            @Valid @RequestBody MilestoneRequest request) {
        logger.info("createMilestone called for customer: {}, project: {}", customerId, projectId);
        MilestoneResponse response = milestoneService.createMilestone(customerId, projectId, request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.id())
                .toUri();

        logger.info("createMilestone returning milestone id: {}", response.id());
        return ResponseEntity.created(location).body(response);
    }

    @GetMapping
    @Operation(summary = "List milestones", description = "Lists all milestones for a project ordered by sort order")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "List of milestones"),
        @ApiResponse(responseCode = "404", description = "Customer or project not found")
    })
    public ResponseEntity<List<MilestoneResponse>> getMilestones(
            @PathVariable String customerId,
            @PathVariable Long projectId) {
        logger.info("getMilestones called for customer: {}, project: {}", customerId, projectId);
        List<MilestoneResponse> milestones = milestoneService.getMilestones(customerId, projectId);
        logger.info("getMilestones returning {} milestones", milestones.size());
        return ResponseEntity.ok(milestones);
    }

    @PutMapping("/{milestoneId}")
    @Operation(summary = "Update milestone", description = "Updates an existing milestone")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Milestone updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Customer, project, or milestone not found"),
        @ApiResponse(responseCode = "409", description = "Sort order conflict or invalid status")
    })
    public ResponseEntity<MilestoneResponse> updateMilestone(
            @PathVariable String customerId,
            @PathVariable Long projectId,
            @PathVariable Long milestoneId,
            @Valid @RequestBody MilestoneUpdateRequest request) {
        logger.info("updateMilestone called for customer: {}, project: {}, milestone: {}", customerId, projectId, milestoneId);
        MilestoneResponse response = milestoneService.updateMilestone(customerId, projectId, milestoneId, request);
        logger.info("updateMilestone returning milestone: {}", milestoneId);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{milestoneId}")
    @Operation(summary = "Delete milestone", description = "Permanently deletes a milestone")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Milestone deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Customer, project, or milestone not found")
    })
    public ResponseEntity<Void> deleteMilestone(
            @PathVariable String customerId,
            @PathVariable Long projectId,
            @PathVariable Long milestoneId) {
        logger.info("deleteMilestone called for customer: {}, project: {}, milestone: {}", customerId, projectId, milestoneId);
        milestoneService.deleteMilestone(customerId, projectId, milestoneId);
        logger.info("deleteMilestone completed for milestone: {}", milestoneId);
        return ResponseEntity.noContent().build();
    }
}
