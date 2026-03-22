package com.hr.repository;

import com.hr.model.Application;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ApplicationRepository extends JpaRepository<Application, String> {

    List<Application> findByApplicantNameContainingIgnoreCase(String applicantName);

    List<Application> findByStatusContainingIgnoreCase(String status);

    List<Application> findByJobId(String jobId);
}
