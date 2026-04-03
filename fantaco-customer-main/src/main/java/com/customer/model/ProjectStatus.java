package com.customer.model;

import java.util.Map;
import java.util.Set;

public enum ProjectStatus {
    PROPOSAL,
    APPROVED,
    IN_PROGRESS,
    ON_HOLD,
    COMPLETED,
    CANCELLED;

    private static final Map<ProjectStatus, Set<ProjectStatus>> TRANSITIONS = Map.of(
            PROPOSAL, Set.of(APPROVED, CANCELLED),
            APPROVED, Set.of(IN_PROGRESS, ON_HOLD, CANCELLED),
            IN_PROGRESS, Set.of(ON_HOLD, COMPLETED, CANCELLED),
            ON_HOLD, Set.of(IN_PROGRESS, CANCELLED),
            COMPLETED, Set.of(),
            CANCELLED, Set.of()
    );

    public boolean canTransitionTo(ProjectStatus target) {
        return TRANSITIONS.getOrDefault(this, Set.of()).contains(target);
    }
}
