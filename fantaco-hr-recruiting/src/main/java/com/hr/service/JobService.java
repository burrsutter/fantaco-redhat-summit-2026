package com.hr.service;

import com.hr.dto.JobRequest;
import com.hr.dto.JobResponse;
import com.hr.dto.JobUpdateRequest;
import com.hr.exception.JobNotFoundException;
import com.hr.exception.DuplicateJobIdException;
import com.hr.model.Job;
import com.hr.repository.JobRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Service
@Transactional
public class JobService {

    private final JobRepository jobRepository;

    public JobService(JobRepository jobRepository) {
        this.jobRepository = jobRepository;
    }

    public JobResponse createJob(JobRequest request) {
        if (jobRepository.existsById(request.jobId())) {
            throw new DuplicateJobIdException(
                "Job with ID " + request.jobId() + " already exists");
        }

        Job job = new Job();
        job.setJobId(request.jobId());
        job.setTitle(request.title());
        job.setDescription(request.description());
        job.setPostedAt(request.postedAt() != null ? request.postedAt() : LocalDateTime.now());
        job.setStatus(request.status());

        try {
            Job saved = jobRepository.save(job);
            return toResponse(saved);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicateJobIdException(
                "Job with ID " + request.jobId() + " already exists");
        }
    }

    @Transactional(readOnly = true)
    public JobResponse getJobById(String jobId) {
        Job job = jobRepository.findById(jobId)
                .orElseThrow(() -> new JobNotFoundException(
                    "Job with ID " + jobId + " not found"));
        return toResponse(job);
    }

    @Transactional(readOnly = true)
    public List<JobResponse> searchJobs(String title, String status) {
        boolean hasAnyCriteria = (title != null && !title.isBlank())
                || (status != null && !status.isBlank());

        if (!hasAnyCriteria) {
            return jobRepository.findAll().stream()
                    .map(this::toResponse)
                    .toList();
        }

        List<Job> results = null;

        if (title != null && !title.isBlank()) {
            results = new ArrayList<>(
                jobRepository.findByTitleContainingIgnoreCase(title));
        }
        if (status != null && !status.isBlank()) {
            List<Job> matched =
                jobRepository.findByStatusContainingIgnoreCase(status);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }

        return results.stream().map(this::toResponse).toList();
    }

    public JobResponse updateJob(String jobId, JobUpdateRequest request) {
        Job job = jobRepository.findById(jobId)
                .orElseThrow(() -> new JobNotFoundException(
                    "Job with ID " + jobId + " not found"));

        job.setTitle(request.title());
        job.setDescription(request.description());
        if (request.postedAt() != null) {
            job.setPostedAt(request.postedAt());
        }
        job.setStatus(request.status());

        Job updated = jobRepository.save(job);
        return toResponse(updated);
    }

    public void deleteJob(String jobId) {
        if (!jobRepository.existsById(jobId)) {
            throw new JobNotFoundException(
                "Job with ID " + jobId + " not found");
        }
        jobRepository.deleteById(jobId);
    }

    private List<Job> intersect(List<Job> a, List<Job> b) {
        List<Job> result = new ArrayList<>(a);
        result.retainAll(b);
        return result;
    }

    private JobResponse toResponse(Job job) {
        return new JobResponse(
                job.getJobId(),
                job.getTitle(),
                job.getDescription(),
                job.getPostedAt(),
                job.getStatus(),
                job.getCreatedAt(),
                job.getUpdatedAt()
        );
    }
}
