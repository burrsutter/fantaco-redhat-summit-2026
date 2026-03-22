package com.hr.controller;

import com.hr.dto.ApplicationRequest;
import com.hr.dto.ApplicationResponse;
import com.hr.dto.ApplicationUpdateRequest;
import com.hr.service.ApplicationService;
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
@RequestMapping("/api/applications")
@CrossOrigin(origins = "*")
@Tag(name = "Application", description = "Job application management operations")
public class ApplicationController {

    private static final Logger logger = LoggerFactory.getLogger(ApplicationController.class);

    private final ApplicationService applicationService;

    public ApplicationController(ApplicationService applicationService) {
        this.applicationService = applicationService;
    }

    @PostMapping
    @Operation(summary = "Submit a job application",
               description = "Creates a new job application with the provided information")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Application submitted successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "409", description = "Application ID already exists")
    })
    public ResponseEntity<ApplicationResponse> createApplication(
            @Valid @RequestBody ApplicationRequest request) {
        logger.info("createApplication called with application ID: {}", request.applicationId());
        ApplicationResponse response = applicationService.createApplication(request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{applicationId}")
                .buildAndExpand(response.applicationId())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @GetMapping("/{applicationId}")
    @Operation(summary = "Get application by ID",
               description = "Retrieves a single application by its unique identifier")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Application found"),
        @ApiResponse(responseCode = "404", description = "Application not found")
    })
    public ResponseEntity<ApplicationResponse> getApplicationById(
            @PathVariable String applicationId) {
        logger.info("getApplicationById called with application ID: {}", applicationId);
        ApplicationResponse response = applicationService.getApplicationById(applicationId);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    @Operation(summary = "Search applications",
               description = "Search for applications by applicant name, status, or job ID")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200",
                     description = "List of applications matching the search criteria")
    })
    public ResponseEntity<List<ApplicationResponse>> searchApplications(
            @RequestParam(required = false) String applicantName,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String jobId) {
        logger.info("searchApplications called with applicantName: {}, status: {}, jobId: {}",
                applicantName, status, jobId);
        List<ApplicationResponse> applications =
            applicationService.searchApplications(applicantName, status, jobId);
        return ResponseEntity.ok(applications);
    }

    @PutMapping("/{applicationId}")
    @Operation(summary = "Update application",
               description = "Updates an existing application record")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Application updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Application not found")
    })
    public ResponseEntity<ApplicationResponse> updateApplication(
            @PathVariable String applicationId,
            @Valid @RequestBody ApplicationUpdateRequest request) {
        logger.info("updateApplication called with application ID: {}", applicationId);
        ApplicationResponse response = applicationService.updateApplication(applicationId, request);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{applicationId}")
    @Operation(summary = "Delete application",
               description = "Permanently deletes an application record (hard delete)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Application deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Application not found")
    })
    public ResponseEntity<Void> deleteApplication(@PathVariable String applicationId) {
        logger.info("deleteApplication called with application ID: {}", applicationId);
        applicationService.deleteApplication(applicationId);
        return ResponseEntity.noContent().build();
    }
}
