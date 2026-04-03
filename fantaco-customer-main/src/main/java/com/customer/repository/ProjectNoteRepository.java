package com.customer.repository;

import com.customer.model.ProjectNote;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProjectNoteRepository extends JpaRepository<ProjectNote, Long> {

    List<ProjectNote> findByProjectIdOrderByCreatedAtDesc(Long projectId);
}
