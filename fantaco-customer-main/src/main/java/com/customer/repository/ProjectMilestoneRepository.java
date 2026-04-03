package com.customer.repository;

import com.customer.model.ProjectMilestone;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProjectMilestoneRepository extends JpaRepository<ProjectMilestone, Long> {

    List<ProjectMilestone> findByProjectIdOrderBySortOrderAsc(Long projectId);
}
