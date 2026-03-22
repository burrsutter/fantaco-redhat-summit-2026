package com.hr.service;

import com.hr.dto.ApplicationRequest;
import com.hr.dto.ApplicationResponse;
import com.hr.dto.ApplicationUpdateRequest;
import com.hr.exception.ApplicationNotFoundException;
import com.hr.exception.DuplicateApplicationIdException;
import com.hr.model.Application;
import com.hr.repository.ApplicationRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Service
@Transactional
public class ApplicationService {

    private final ApplicationRepository applicationRepository;

    public ApplicationService(ApplicationRepository applicationRepository) {
        this.applicationRepository = applicationRepository;
    }

    public ApplicationResponse createApplication(ApplicationRequest request) {
        if (applicationRepository.existsById(request.applicationId())) {
            throw new DuplicateApplicationIdException(
                "Application with ID " + request.applicationId() + " already exists");
        }

        Application application = new Application();
        application.setApplicationId(request.applicationId());
        application.setJobId(request.jobId());
        application.setApplicantName(request.applicantName());
        application.setApplicantEmail(request.applicantEmail());
        application.setResumeData(request.resumeData());
        application.setStatus(request.status());
        application.setSubmittedAt(request.submittedAt() != null ? request.submittedAt() : LocalDateTime.now());

        try {
            Application saved = applicationRepository.save(application);
            return toResponse(saved);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicateApplicationIdException(
                "Application with ID " + request.applicationId() + " already exists");
        }
    }

    @Transactional(readOnly = true)
    public ApplicationResponse getApplicationById(String applicationId) {
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new ApplicationNotFoundException(
                    "Application with ID " + applicationId + " not found"));
        return toResponse(application);
    }

    @Transactional(readOnly = true)
    public List<ApplicationResponse> searchApplications(String applicantName, String status, String jobId) {
        boolean hasAnyCriteria = (applicantName != null && !applicantName.isBlank())
                || (status != null && !status.isBlank())
                || (jobId != null && !jobId.isBlank());

        if (!hasAnyCriteria) {
            return applicationRepository.findAll().stream()
                    .map(this::toResponse)
                    .toList();
        }

        List<Application> results = null;

        if (applicantName != null && !applicantName.isBlank()) {
            results = new ArrayList<>(
                applicationRepository.findByApplicantNameContainingIgnoreCase(applicantName));
        }
        if (status != null && !status.isBlank()) {
            List<Application> matched =
                applicationRepository.findByStatusContainingIgnoreCase(status);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }
        if (jobId != null && !jobId.isBlank()) {
            List<Application> matched =
                applicationRepository.findByJobId(jobId);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }

        return results.stream().map(this::toResponse).toList();
    }

    public ApplicationResponse updateApplication(String applicationId, ApplicationUpdateRequest request) {
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new ApplicationNotFoundException(
                    "Application with ID " + applicationId + " not found"));

        application.setJobId(request.jobId());
        application.setApplicantName(request.applicantName());
        application.setApplicantEmail(request.applicantEmail());
        application.setResumeData(request.resumeData());
        application.setStatus(request.status());
        if (request.submittedAt() != null) {
            application.setSubmittedAt(request.submittedAt());
        }

        Application updated = applicationRepository.save(application);
        return toResponse(updated);
    }

    public void deleteApplication(String applicationId) {
        if (!applicationRepository.existsById(applicationId)) {
            throw new ApplicationNotFoundException(
                "Application with ID " + applicationId + " not found");
        }
        applicationRepository.deleteById(applicationId);
    }

    private List<Application> intersect(List<Application> a, List<Application> b) {
        List<Application> result = new ArrayList<>(a);
        result.retainAll(b);
        return result;
    }

    private ApplicationResponse toResponse(Application app) {
        return new ApplicationResponse(
                app.getApplicationId(),
                app.getJobId(),
                app.getApplicantName(),
                app.getApplicantEmail(),
                app.getResumeData(),
                app.getStatus(),
                app.getSubmittedAt(),
                app.getCreatedAt(),
                app.getUpdatedAt()
        );
    }
}
