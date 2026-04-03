package com.customer.repository;

import com.customer.model.PodTheme;
import com.customer.model.Project;
import com.customer.model.ProjectStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProjectRepository extends JpaRepository<Project, Long> {

    List<Project> findByCustomerCustomerId(String customerId);

    List<Project> findByCustomerCustomerIdAndStatus(String customerId, ProjectStatus status);

    List<Project> findByCustomerCustomerIdAndPodTheme(String customerId, PodTheme podTheme);

    List<Project> findByCustomerCustomerIdAndStatusAndPodTheme(String customerId, ProjectStatus status, PodTheme podTheme);
}
