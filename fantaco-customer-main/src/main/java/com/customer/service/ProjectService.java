package com.customer.service;

import com.customer.dto.*;
import com.customer.exception.InvalidStatusTransitionException;
import com.customer.exception.ResourceNotFoundException;
import com.customer.model.*;
import com.customer.repository.CustomerRepository;
import com.customer.repository.ProjectNoteRepository;
import com.customer.repository.ProjectRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;

@Service
@Transactional
public class ProjectService {

    private final ProjectRepository projectRepository;
    private final ProjectNoteRepository projectNoteRepository;
    private final CustomerRepository customerRepository;

    public ProjectService(ProjectRepository projectRepository,
                          ProjectNoteRepository projectNoteRepository,
                          CustomerRepository customerRepository) {
        this.projectRepository = projectRepository;
        this.projectNoteRepository = projectNoteRepository;
        this.customerRepository = customerRepository;
    }

    @Transactional(readOnly = true)
    public List<ProjectResponse> getProjectsByCustomerId(String customerId, ProjectStatus status, PodTheme podTheme) {
        verifyCustomerExists(customerId);

        List<Project> projects;
        if (status != null && podTheme != null) {
            projects = projectRepository.findByCustomerCustomerIdAndStatusAndPodTheme(customerId, status, podTheme);
        } else if (status != null) {
            projects = projectRepository.findByCustomerCustomerIdAndStatus(customerId, status);
        } else if (podTheme != null) {
            projects = projectRepository.findByCustomerCustomerIdAndPodTheme(customerId, podTheme);
        } else {
            projects = projectRepository.findByCustomerCustomerId(customerId);
        }

        return projects.stream().map(this::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public ProjectDetailResponse getProjectDetailById(String customerId, Long projectId) {
        verifyCustomerExists(customerId);
        Project project = verifyProjectOwnership(customerId, projectId);
        return toDetailResponse(project);
    }

    public ProjectResponse createProject(String customerId, ProjectRequest request) {
        Customer customer = customerRepository.findById(customerId)
                .orElseThrow(() -> new ResourceNotFoundException("Customer with ID " + customerId + " not found"));

        Project project = new Project();
        project.setProjectName(request.projectName());
        project.setDescription(request.description());
        project.setPodTheme(request.podTheme());
        project.setStatus(ProjectStatus.PROPOSAL);
        project.setSiteAddress(request.siteAddress());
        project.setEstimatedStartDate(request.estimatedStartDate());
        project.setEstimatedEndDate(request.estimatedEndDate());
        project.setEstimatedBudget(request.estimatedBudget());
        project.setCustomer(customer);

        Project saved = projectRepository.save(project);
        return toResponse(saved);
    }

    public ProjectResponse updateProject(String customerId, Long projectId, ProjectUpdateRequest request) {
        verifyCustomerExists(customerId);
        Project project = verifyProjectOwnership(customerId, projectId);

        // Validate status transition
        ProjectStatus currentStatus = project.getStatus();
        ProjectStatus newStatus = request.status();
        if (currentStatus != newStatus && !currentStatus.canTransitionTo(newStatus)) {
            throw new InvalidStatusTransitionException(
                    "Cannot transition project status from " + currentStatus + " to " + newStatus);
        }

        // Validate date requirements based on status
        if ((newStatus == ProjectStatus.IN_PROGRESS || newStatus == ProjectStatus.COMPLETED)
                && request.actualStartDate() == null) {
            throw new InvalidStatusTransitionException(
                    "Actual start date is required when status is " + newStatus);
        }
        if (newStatus == ProjectStatus.COMPLETED && request.actualEndDate() == null) {
            throw new InvalidStatusTransitionException(
                    "Actual end date is required when status is COMPLETED");
        }

        project.setProjectName(request.projectName());
        project.setDescription(request.description());
        project.setPodTheme(request.podTheme());
        project.setStatus(newStatus);
        project.setSiteAddress(request.siteAddress());
        project.setEstimatedStartDate(request.estimatedStartDate());
        project.setEstimatedEndDate(request.estimatedEndDate());
        project.setActualStartDate(request.actualStartDate());
        project.setActualEndDate(request.actualEndDate());
        project.setEstimatedBudget(request.estimatedBudget());
        project.setActualCost(request.actualCost());

        Project saved = projectRepository.save(project);
        return toResponse(saved);
    }

    public void deleteProject(String customerId, Long projectId) {
        verifyCustomerExists(customerId);
        Project project = verifyProjectOwnership(customerId, projectId);
        projectRepository.delete(project);
    }

    public ProjectNoteResponse createProjectNote(String customerId, Long projectId, ProjectNoteRequest request) {
        verifyCustomerExists(customerId);
        Project project = verifyProjectOwnership(customerId, projectId);

        ProjectNote note = new ProjectNote();
        note.setNoteText(request.noteText());
        note.setNoteType(request.noteType());
        note.setAuthor(request.author());
        project.addProjectNote(note);

        ProjectNote saved = projectNoteRepository.save(note);
        return toNoteResponse(saved, projectId);
    }

    @Transactional(readOnly = true)
    public List<ProjectNoteResponse> getProjectNotes(String customerId, Long projectId) {
        verifyCustomerExists(customerId);
        verifyProjectOwnership(customerId, projectId);
        return projectNoteRepository.findByProjectIdOrderByCreatedAtDesc(projectId).stream()
                .map(note -> toNoteResponse(note, projectId))
                .toList();
    }

    public void deleteProjectNote(String customerId, Long projectId, Long noteId) {
        verifyCustomerExists(customerId);
        Project project = verifyProjectOwnership(customerId, projectId);
        ProjectNote note = projectNoteRepository.findById(noteId)
                .orElseThrow(() -> new ResourceNotFoundException("Project note with ID " + noteId + " not found"));
        if (!note.getProject().getId().equals(projectId)) {
            throw new ResourceNotFoundException("Project note with ID " + noteId + " not found in project " + projectId);
        }
        project.removeProjectNote(note);
        projectNoteRepository.delete(note);
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

    private ProjectResponse toResponse(Project project) {
        return new ProjectResponse(
                project.getId(),
                project.getCustomer().getCustomerId(),
                project.getProjectName(),
                project.getDescription(),
                project.getPodTheme(),
                project.getStatus(),
                project.getSiteAddress(),
                project.getEstimatedStartDate(),
                project.getEstimatedEndDate(),
                project.getActualStartDate(),
                project.getActualEndDate(),
                project.getEstimatedBudget(),
                project.getActualCost(),
                project.getCreatedAt(),
                project.getUpdatedAt()
        );
    }

    private ProjectDetailResponse toDetailResponse(Project project) {
        List<MilestoneResponse> milestoneResponses = project.getMilestones().stream()
                .sorted(Comparator.comparing(ProjectMilestone::getSortOrder))
                .map(m -> new MilestoneResponse(
                        m.getId(),
                        project.getId(),
                        m.getName(),
                        m.getStatus(),
                        m.getDueDate(),
                        m.getCompletedDate(),
                        m.getNotes(),
                        m.getSortOrder(),
                        m.getCreatedAt(),
                        m.getUpdatedAt()
                ))
                .toList();

        List<ProjectNoteResponse> noteResponses = project.getProjectNotes().stream()
                .sorted(Comparator.comparing(ProjectNote::getCreatedAt).reversed())
                .map(n -> toNoteResponse(n, project.getId()))
                .toList();

        return new ProjectDetailResponse(
                project.getId(),
                project.getCustomer().getCustomerId(),
                project.getProjectName(),
                project.getDescription(),
                project.getPodTheme(),
                project.getStatus(),
                project.getSiteAddress(),
                project.getEstimatedStartDate(),
                project.getEstimatedEndDate(),
                project.getActualStartDate(),
                project.getActualEndDate(),
                project.getEstimatedBudget(),
                project.getActualCost(),
                project.getCreatedAt(),
                project.getUpdatedAt(),
                milestoneResponses,
                noteResponses
        );
    }

    private ProjectNoteResponse toNoteResponse(ProjectNote note, Long projectId) {
        return new ProjectNoteResponse(
                note.getId(),
                projectId,
                note.getNoteText(),
                note.getNoteType(),
                note.getAuthor(),
                note.getCreatedAt()
        );
    }
}
