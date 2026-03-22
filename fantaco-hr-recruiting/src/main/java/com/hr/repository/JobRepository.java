package com.hr.repository;

import com.hr.model.Job;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface JobRepository extends JpaRepository<Job, String> {

    List<Job> findByTitleContainingIgnoreCase(String title);

    List<Job> findByStatusContainingIgnoreCase(String status);
}
