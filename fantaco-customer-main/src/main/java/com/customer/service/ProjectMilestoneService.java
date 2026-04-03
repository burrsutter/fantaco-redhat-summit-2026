package com.customer.service;

import com.customer.dto.MilestoneRequest;
import com.customer.dto.MilestoneResponse;
import com.customer.dto.MilestoneUpdateRequest;
import com.customer.exception.InvalidStatusTransitionException;
import com.customer.exception.ResourceNotFoundException;
import com.customer.model.MilestoneStatus;
import com.customer.model.Project;
import com.customer.model.ProjectMilestone;
import com.customer.repository.CustomerRepository;
import com.customer.repository.ProjectMilestoneRepository;
import com.customer.repository.ProjectRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class ProjectMilestoneService {

    private final ProjectMilestoneRepository milestoneRepository;
    private final ProjectRepository projectRepository;
    private final CustomerRepository customerRepository;

    public ProjectMilestoneService(ProjectMilestoneRepository milestoneRepository,
                                   ProjectRepository projectRepository,
                                   CustomerRepository customerRepository) {
        this.milestoneRepository = milestoneRepository;
        this.projectRepository = projectRepository;
        this.customerRepository = customerRepository;
    }

    @Transactional(readOnly = true)
    public List<MilestoneResponse> getMilestones(String customerId, Long projectId) {
        verifyCustomerExists(customerId);
        verifyProjectOwnership(customerId, projectId);
        return milestoneRepository.findByProjectIdOrderBySortOrderAsc(projectId).stream()
                .map(m -> toResponse(m, projectId))
                .toList();
    }

    public MilestoneResponse createMilestone(String customerId, Long projectId, MilestoneRequest request) {
        verifyCustomerExists(customerId);
        Project project = verifyProjectOwnership(customerId, projectId);

        ProjectMilestone milestone = new ProjectMilestone();
        milestone.setName(request.name());
        milestone.setStatus(MilestoneStatus.NOT_STARTED);
        milestone.setDueDate(request.dueDate());
        milestone.setNotes(request.notes());
        milestone.setSortOrder(request.sortOrder());
        project.addMilestone(milestone);

        try {
            ProjectMilestone saved = milestoneRepository.save(milestone);
            return toResponse(saved, projectId);
        } catch (DataIntegrityViolationException e) {
            throw new InvalidStatusTransitionException(
                    "Sort order " + request.sortOrder() + " already exists for project " + projectId);
        }
    }

    public MilestoneResponse updateMilestone(String customerId, Long projectId, Long milestoneId,
                                             MilestoneUpdateRequest request) {
        verifyCustomerExists(customerId);
        verifyProjectOwnership(customerId, projectId);
        ProjectMilestone milestone = verifyMilestoneOwnership(projectId, milestoneId);

        // Validate completedDate
        if (request.status() == MilestoneStatus.COMPLETED && request.completedDate() == null) {
            throw new InvalidStatusTransitionException(
                    "Completed date is required when milestone status is COMPLETED");
        }
        if (request.status() != MilestoneStatus.COMPLETED && request.completedDate() != null) {
            throw new InvalidStatusTransitionException(
                    "Completed date must be null when milestone status is not COMPLETED");
        }

        milestone.setName(request.name());
        milestone.setStatus(request.status());
        milestone.setDueDate(request.dueDate());
        milestone.setCompletedDate(request.completedDate());
        milestone.setNotes(request.notes());
        milestone.setSortOrder(request.sortOrder());

        try {
            ProjectMilestone saved = milestoneRepository.save(milestone);
            return toResponse(saved, projectId);
        } catch (DataIntegrityViolationException e) {
            throw new InvalidStatusTransitionException(
                    "Sort order " + request.sortOrder() + " already exists for project " + projectId);
        }
    }

    public void deleteMilestone(String customerId, Long projectId, Long milestoneId) {
        verifyCustomerExists(customerId);
        Project project = verifyProjectOwnership(customerId, projectId);
        ProjectMilestone milestone = verifyMilestoneOwnership(projectId, milestoneId);
        project.removeMilestone(milestone);
        milestoneRepository.delete(milestone);
    }

    private void verifyCustomerExists(String customerId) {
        if (!customerRepository.existsById(customerId)) {
            throw new ResourceNotFoundException("Customer with ID " + customerId + " not found");
        }
    }

    private Project verifyProjectOwnership(String customerId, Long projectId) {
        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ResourceNotFoundException("Project with ID " + projectId + " not found"));
        if (!project.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Project with ID " + projectId + " not found for customer " + customerId);
        }
        return project;
    }

    private ProjectMilestone verifyMilestoneOwnership(Long projectId, Long milestoneId) {
        ProjectMilestone milestone = milestoneRepository.findById(milestoneId)
                .orElseThrow(() -> new ResourceNotFoundException("Milestone with ID " + milestoneId + " not found"));
        if (!milestone.getProject().getId().equals(projectId)) {
            throw new ResourceNotFoundException("Milestone with ID " + milestoneId + " not found in project " + projectId);
        }
        return milestone;
    }

    private MilestoneResponse toResponse(ProjectMilestone milestone, Long projectId) {
        return new MilestoneResponse(
                milestone.getId(),
                projectId,
                milestone.getName(),
                milestone.getStatus(),
                milestone.getDueDate(),
                milestone.getCompletedDate(),
                milestone.getNotes(),
                milestone.getSortOrder(),
                milestone.getCreatedAt(),
                milestone.getUpdatedAt()
        );
    }
}
