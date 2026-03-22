package com.hr.controller;

import com.hr.dto.JobRequest;
import com.hr.dto.JobResponse;
import com.hr.dto.JobUpdateRequest;
import com.hr.service.JobService;
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
@RequestMapping("/api/jobs")
@CrossOrigin(origins = "*")
@Tag(name = "Job", description = "Job posting management operations")
public class JobController {

    private static final Logger logger = LoggerFactory.getLogger(JobController.class);

    private final JobService jobService;

    public JobController(JobService jobService) {
        this.jobService = jobService;
    }

    @PostMapping
    @Operation(summary = "Create a new job posting",
               description = "Creates a new job posting with the provided information")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Job created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "409", description = "Job ID already exists")
    })
    public ResponseEntity<JobResponse> createJob(
            @Valid @RequestBody JobRequest request) {
        logger.info("createJob called with job ID: {}", request.jobId());
        JobResponse response = jobService.createJob(request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{jobId}")
                .buildAndExpand(response.jobId())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @GetMapping("/{jobId}")
    @Operation(summary = "Get job by ID",
               description = "Retrieves a single job posting by its unique identifier")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Job found"),
        @ApiResponse(responseCode = "404", description = "Job not found")
    })
    public ResponseEntity<JobResponse> getJobById(@PathVariable String jobId) {
        logger.info("getJobById called with job ID: {}", jobId);
        JobResponse response = jobService.getJobById(jobId);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    @Operation(summary = "Search jobs",
               description = "Search for jobs by title or status with partial matching")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200",
                     description = "List of jobs matching the search criteria")
    })
    public ResponseEntity<List<JobResponse>> searchJobs(
            @RequestParam(required = false) String title,
            @RequestParam(required = false) String status) {
        logger.info("searchJobs called with title: {}, status: {}", title, status);
        List<JobResponse> jobs = jobService.searchJobs(title, status);
        return ResponseEntity.ok(jobs);
    }

    @PutMapping("/{jobId}")
    @Operation(summary = "Update job posting",
               description = "Updates an existing job posting")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Job updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Job not found")
    })
    public ResponseEntity<JobResponse> updateJob(
            @PathVariable String jobId,
            @Valid @RequestBody JobUpdateRequest request) {
        logger.info("updateJob called with job ID: {}", jobId);
        JobResponse response = jobService.updateJob(jobId, request);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{jobId}")
    @Operation(summary = "Delete job posting",
               description = "Permanently deletes a job posting (hard delete)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Job deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Job not found")
    })
    public ResponseEntity<Void> deleteJob(@PathVariable String jobId) {
        logger.info("deleteJob called with job ID: {}", jobId);
        jobService.deleteJob(jobId);
        return ResponseEntity.noContent().build();
    }
}
