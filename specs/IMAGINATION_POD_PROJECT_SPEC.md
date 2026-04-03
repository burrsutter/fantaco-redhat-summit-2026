# Imagination Pod Project Management — CRM Extension Spec

> **Purpose:** Extend the `fantaco-customer-main` CRM module with project management capabilities to support FantaCo's new Imagination Pod office construction business. Each project tracks the design, construction, and delivery of a themed workspace for a customer.

---

## Business Context

FantaCo is expanding from selling office supplies into **light construction of themed office spaces** based on the Imagination Pod concept — fully customizable workspaces with themes like Enchanted Forest, Interstellar Spaceship, 1920s Speakeasy, and Serene Zen Garden. The CRM must track each build-out as a project tied to a customer account, with milestones, status, budget, and a running log of project notes.

### What This Is

- Simple project tracking scoped to a customer account
- Milestones that represent natural construction phases
- Project-specific notes for site visits, change orders, status updates
- Budget tracking (estimated vs. actual)
- Timeline tracking (estimated vs. actual dates)

### What This Is NOT

- Not a full project management tool (no Gantt charts, dependency graphs, resource scheduling)
- Not a billing/invoicing system (that belongs in the finance module)
- Not a file/document management system (floor plans, photos are out of scope for v1)

---

## Data Model

### New Entity: `Project`

Belongs to `Customer` via `customer_id`. One customer can have multiple projects.

| Field | Type | Max Length | Required | Constraints | Indexed | Searchable | Notes |
|-------|------|-----------|----------|-------------|---------|------------|-------|
| id | Long | — | auto | `@GeneratedValue(IDENTITY)` | PK | — | Auto-generated |
| customer_id | String | 10 | true | FK → `customer.customer_id` | true | — | Owning customer |
| project_name | String | 200 | true | `@NotBlank` | true | true | e.g. "HQ 3rd Floor Zen Garden Build-Out" |
| pod_theme | String (enum) | 30 | true | `@NotNull` | true | true | See Pod Theme enum below |
| description | String (TEXT) | 2000 | false | — | false | false | Scope narrative |
| status | String (enum) | 20 | true | `@NotNull` | true | true | See Project Status enum below |
| site_address | String | 500 | false | — | false | false | Where the work happens (may differ from customer address) |
| estimated_start_date | LocalDate | — | false | — | false | false | Planned start |
| estimated_end_date | LocalDate | — | false | — | false | false | Planned completion |
| actual_start_date | LocalDate | — | false | — | false | false | Nullable until work begins |
| actual_end_date | LocalDate | — | false | — | false | false | Nullable until work completes |
| estimated_budget | BigDecimal | 12,2 | false | `@DecimalMin("0.00")` | false | false | Quoted cost |
| actual_cost | BigDecimal | 12,2 | false | `@DecimalMin("0.00")` | false | false | Running/final cost |
| created_at | LocalDateTime | — | auto | `@CreationTimestamp` | false | false | |
| updated_at | LocalDateTime | — | auto | `@UpdateTimestamp` | false | false | |

#### Project Validation Rules

- `project_name` must be unique per customer only if the team explicitly adds a unique constraint later; v1 does not enforce uniqueness.
- `estimated_start_date` and `estimated_end_date`, when both present, must satisfy `estimated_start_date <= estimated_end_date`.
- `actual_start_date` and `actual_end_date`, when both present, must satisfy `actual_start_date <= actual_end_date`.
- `estimated_budget` and `actual_cost` must be zero or greater.
- `actual_start_date`, `actual_end_date`, and `actual_cost` are optional on create.
- `actual_end_date` must be present when `status = COMPLETED`.
- `actual_start_date` must be present when `status = IN_PROGRESS` or `status = COMPLETED`.
- `actual_cost` may exceed `estimated_budget`; this is a tracked variance, not a validation error.
- `site_address` is optional and may differ from the customer account address.

### New Entity: `ProjectMilestone`

Belongs to `Project` via `project_id`. Ordered phases within a project.

| Field | Type | Max Length | Required | Constraints | Indexed | Searchable | Notes |
|-------|------|-----------|----------|-------------|---------|------------|-------|
| id | Long | — | auto | `@GeneratedValue(IDENTITY)` | PK | — | |
| project_id | Long | — | true | FK → `project.id` | true | — | Owning project |
| name | String | 150 | true | `@NotBlank` | false | false | e.g. "Site Assessment", "Theme Design Approval" |
| status | String (enum) | 20 | true | `@NotNull` | false | false | See Milestone Status enum below |
| due_date | LocalDate | — | false | — | false | false | Target completion date |
| completed_date | LocalDate | — | false | — | false | false | Actual completion date |
| notes | String (TEXT) | 1000 | false | — | false | false | Progress or blocker context |
| sort_order | Integer | — | true | `@NotNull`, `@Min(0)` | false | false | Display ordering within the project |
| created_at | LocalDateTime | — | auto | `@CreationTimestamp` | false | false | |
| updated_at | LocalDateTime | — | auto | `@UpdateTimestamp` | false | false | |

#### Milestone Validation Rules

- `sort_order` is required and must be unique within a project.
- Add a database unique constraint on `(project_id, sort_order)`.
- Gaps in `sort_order` are allowed in storage, but list endpoints must always return milestones ordered ascending by `sort_order`.
- `completed_date` may only be set when `status = COMPLETED`.
- If `status != COMPLETED`, `completed_date` must be null.
- `due_date` is optional.

### New Entity: `ProjectNote`

Belongs to `Project` via `project_id`. Project-specific interaction log, separate from `CustomerNote`.

| Field | Type | Max Length | Required | Constraints | Indexed | Searchable | Notes |
|-------|------|-----------|----------|-------------|---------|------------|-------|
| id | Long | — | auto | `@GeneratedValue(IDENTITY)` | PK | — | |
| project_id | Long | — | true | FK → `project.id` | true | — | Owning project |
| note_text | String (TEXT) | — | true | `@NotBlank` | false | false | The note content |
| note_type | String (enum) | 20 | true | `@NotNull` | false | false | See Note Type enum below |
| author | String | 100 | false | — | false | false | Who wrote it |
| created_at | LocalDateTime | — | auto | `@CreationTimestamp` | false | false | |

#### Project Note Rules

- Project notes are append-only in v1.
- There is no note update endpoint in v1.
- `author` is optional; if omitted, persist null rather than a synthetic default.

### Enums

#### PodTheme

| Value | Description |
|-------|-------------|
| `ENCHANTED_FOREST` | Miniature waterfall, animatronic wildlife, nature soundscapes |
| `INTERSTELLAR_SPACESHIP` | Zero-gravity optional, holographic projectors, ambient star fields |
| `SPEAKEASY_1920S` | Password entry, vintage decor, ambient jazz |
| `ZEN_GARDEN` | Bonsai, water features, meditation nooks, calming soundscapes |
| `CUSTOM` | Client-defined theme outside standard offerings |

#### ProjectStatus

| Value | Description |
|-------|-------------|
| `PROPOSAL` | Initial scoping — not yet approved by customer |
| `APPROVED` | Customer has signed off — awaiting scheduling |
| `IN_PROGRESS` | Active construction underway |
| `ON_HOLD` | Paused (supply delay, customer request, etc.) |
| `COMPLETED` | Build-out finished and accepted |
| `CANCELLED` | Project abandoned before completion |

#### MilestoneStatus

| Value | Description |
|-------|-------------|
| `NOT_STARTED` | Work on this phase has not begun |
| `IN_PROGRESS` | Phase is currently active |
| `COMPLETED` | Phase finished |
| `BLOCKED` | Phase cannot proceed (dependency, supply issue, etc.) |

#### ProjectNoteType

| Value | Description |
|-------|-------------|
| `STATUS_UPDATE` | General progress note |
| `CHANGE_ORDER` | Scope or budget change |
| `SITE_VISIT` | On-site inspection or walkthrough |
| `ISSUE` | Problem or blocker |
| `GENERAL` | Catch-all |

---

## Entity Relationships

```
Customer (existing)
├── CustomerNote (existing)
├── CustomerContact (existing)
├── SalesPerson (existing)
└── Project (NEW) ── @OneToMany from Customer, cascade ALL, orphanRemoval
    ├── ProjectMilestone (NEW) ── @OneToMany from Project, cascade ALL, orphanRemoval
    └── ProjectNote (NEW) ── @OneToMany from Project, cascade ALL, orphanRemoval
```

The `Customer` entity gains a new `@OneToMany` relationship to `Project`, following the same pattern as its existing relationships to `CustomerNote`, `CustomerContact`, and `SalesPerson`.

### Ownership and Lookup Rules

- Every project endpoint must first validate that the customer exists.
- `projectId` lookups under `/api/customers/{customerId}` must verify the project belongs to that customer.
- `milestoneId` lookups must verify the milestone belongs to the specified project.
- `noteId` lookups must verify the note belongs to the specified project.
- Ownership mismatches should return `404`, not `403`, to avoid exposing unrelated resource existence.

### Persistence Expectations

- Store enums with `@Enumerated(EnumType.STRING)`.
- Add indexes for:
  - `project.customer_id`
  - `project.project_name`
  - `project.pod_theme`
  - `project.status`
  - `project_milestone.project_id`
  - `project_note.project_id`
- Default collection ordering:
  - projects: newest first by `created_at desc`
  - milestones: `sort_order asc`
  - notes: `created_at desc`
- Child entities must use `@JsonIgnore` on parent back-references to avoid recursion in JSON serialization.

---

## Business Rules

### Project Status Transitions

Allowed transitions in v1:

- `PROPOSAL -> APPROVED`
- `PROPOSAL -> CANCELLED`
- `APPROVED -> IN_PROGRESS`
- `APPROVED -> CANCELLED`
- `IN_PROGRESS -> ON_HOLD`
- `IN_PROGRESS -> COMPLETED`
- `IN_PROGRESS -> CANCELLED`
- `ON_HOLD -> IN_PROGRESS`
- `ON_HOLD -> CANCELLED`

Disallowed transitions:

- Any transition out of `COMPLETED`
- Any transition out of `CANCELLED`
- Skipping directly from `PROPOSAL -> IN_PROGRESS`
- Skipping directly from `APPROVED -> COMPLETED`

Invalid transitions should return `409 Conflict`.

### Project and Milestone Behavior

- Creating a project does not auto-create milestones unless the implementation team explicitly chooses to add a template seeding step; base v1 should require milestone creation through the milestone API or deterministic `data.sql`.
- Updating milestone status does not automatically roll up project status in v1.
- Deleting a project deletes its milestones and notes through cascade behavior.
- Deleting a `COMPLETED` or `CANCELLED` project is allowed in v1 unless business stakeholders later want a retention rule.

---

## API Endpoints

All endpoints nest under the existing `/api/customers/{customerId}` base.

### Project CRUD

| Method | Path | Body | Response | Description |
|--------|------|------|----------|-------------|
| POST | `/api/customers/{customerId}/projects` | `ProjectRequest` | 201 + `ProjectResponse` | Create a project |
| GET | `/api/customers/{customerId}/projects` | query: `status`, `podTheme` | 200 + `List<ProjectResponse>` | List/filter projects for a customer |
| GET | `/api/customers/{customerId}/projects/{projectId}` | — | 200 + `ProjectDetailResponse` | Get project with milestones and notes |
| PUT | `/api/customers/{customerId}/projects/{projectId}` | `ProjectUpdateRequest` | 200 + `ProjectResponse` | Update project |
| DELETE | `/api/customers/{customerId}/projects/{projectId}` | — | 204 | Delete project and children |

Query parameter behavior:

- `status` and `podTheme` are optional and may be combined.
- Enum query parameters are case-sensitive and must use the exact enum token, for example `IN_PROGRESS`.
- If no filters are provided, return all projects for the customer using default ordering.
- Invalid enum query parameter values should return `400 Bad Request`.

### Project Milestones

| Method | Path | Body | Response | Description |
|--------|------|------|----------|-------------|
| POST | `.../projects/{projectId}/milestones` | `MilestoneRequest` | 201 + `MilestoneResponse` | Add a milestone |
| GET | `.../projects/{projectId}/milestones` | — | 200 + `List<MilestoneResponse>` | List milestones (ordered by sort_order) |
| PUT | `.../projects/{projectId}/milestones/{milestoneId}` | `MilestoneUpdateRequest` | 200 + `MilestoneResponse` | Update milestone (status, dates, notes) |
| DELETE | `.../projects/{projectId}/milestones/{milestoneId}` | — | 204 | Remove a milestone |

### Project Notes

| Method | Path | Body | Response | Description |
|--------|------|------|----------|-------------|
| POST | `.../projects/{projectId}/notes` | `ProjectNoteRequest` | 201 + `ProjectNoteResponse` | Add a note |
| GET | `.../projects/{projectId}/notes` | — | 200 + `List<ProjectNoteResponse>` | List notes (newest first) |
| DELETE | `.../projects/{projectId}/notes/{noteId}` | — | 204 | Remove a note |

### Endpoint Error Semantics

Apply the existing shared `ErrorResponse` structure from the customer module.

| Scenario | Status | Notes |
|----------|--------|-------|
| Customer, project, milestone, or note not found | `404` | Includes ownership mismatches |
| Bean validation failure | `400` | Field-level errors in `validationErrors` |
| Invalid enum value in body or query param | `400` | Message should identify the invalid field |
| Illegal project status transition | `409` | Business rule conflict |
| Duplicate milestone `sort_order` within project | `409` | Either from service validation or DB constraint |

### Request/Response Ownership Rules

- Server-owned fields: `id`, `customerId`, `projectId`, `createdAt`, `updatedAt`.
- These fields must not appear in request bodies.
- If clients send server-owned fields, the API may ignore them or reject them; preferred behavior is `400 Bad Request`.
- `POST /projects` returns `ProjectResponse` without child collections.
- `GET /projects/{projectId}` returns `ProjectDetailResponse` with milestones and notes using the default child orderings.
- `PUT` is a full update of mutable project fields, not a JSON merge patch.
- Omitted optional fields in a `PUT` request are treated as null unless the implementation deliberately switches to `PATCH`.

---

## DTOs

### ProjectRequest (Record)

```java
String projectName,          // @NotBlank, @Size(max = 200)
String podTheme,             // @NotBlank — validated against PodTheme enum
String description,          // @Size(max = 2000)
String status,               // @NotBlank — validated against ProjectStatus enum
String siteAddress,          // @Size(max = 500)
LocalDate estimatedStartDate,
LocalDate estimatedEndDate,
BigDecimal estimatedBudget   // @DecimalMin("0.00")
```

Implementation note:

- Prefer enum-typed record fields (`PodTheme podTheme`, `ProjectStatus status`) if the codebase is comfortable with Spring enum binding and OpenAPI generation.
- If string fields are kept, validate case-sensitive exact enum tokens in the service layer and document the accepted values in OpenAPI examples.

### ProjectUpdateRequest (Record)

Same as `ProjectRequest` plus:

```java
LocalDate actualStartDate,
LocalDate actualEndDate,
BigDecimal actualCost        // @DecimalMin("0.00")
```

Additional expectations:

- `PUT` must accept the full mutable project shape.
- `customerId`, `id`, `createdAt`, and `updatedAt` are excluded from all request DTOs.

### ProjectResponse (Record)

All `Project` fields plus `customerId`. No child collections.

Recommended shape:

```java
Long id,
String customerId,
String projectName,
String podTheme,
String description,
String status,
String siteAddress,
LocalDate estimatedStartDate,
LocalDate estimatedEndDate,
LocalDate actualStartDate,
LocalDate actualEndDate,
BigDecimal estimatedBudget,
BigDecimal actualCost,
LocalDateTime createdAt,
LocalDateTime updatedAt
```

### ProjectDetailResponse (Record)

All `ProjectResponse` fields plus:

```java
List<MilestoneResponse> milestones,
List<ProjectNoteResponse> notes
```

### MilestoneRequest (Record)

```java
String name,                 // @NotBlank, @Size(max = 150)
String status,               // @NotBlank — validated against MilestoneStatus enum
LocalDate dueDate,
String notes,                // @Size(max = 1000)
Integer sortOrder            // @NotNull, @Min(0)
```

### MilestoneUpdateRequest (Record)

Same fields as `MilestoneRequest` plus:

```java
LocalDate completedDate
```

### MilestoneResponse (Record)

All `ProjectMilestone` fields plus `projectId`.

### ProjectNoteRequest (Record)

```java
String noteText,             // @NotBlank
String noteType,             // @NotBlank — validated against ProjectNoteType enum
String author                // @Size(max = 100)
```

### ProjectNoteResponse (Record)

All `ProjectNote` fields plus `projectId`.

### Example JSON

#### ProjectRequest Example

```json
{
  "projectName": "HQ 3rd Floor Zen Garden Build-Out",
  "podTheme": "ZEN_GARDEN",
  "description": "Convert the east wing into a themed client wellness collaboration pod.",
  "status": "APPROVED",
  "siteAddress": "123 Main Street, 2nd Floor, Portland, OR 97201",
  "estimatedStartDate": "2026-05-01",
  "estimatedEndDate": "2026-06-15",
  "estimatedBudget": 185000.00
}
```

#### ProjectResponse Example

```json
{
  "id": 42,
  "customerId": "CUST001",
  "projectName": "HQ 3rd Floor Zen Garden Build-Out",
  "podTheme": "ZEN_GARDEN",
  "description": "Convert the east wing into a themed client wellness collaboration pod.",
  "status": "APPROVED",
  "siteAddress": "123 Main Street, 2nd Floor, Portland, OR 97201",
  "estimatedStartDate": "2026-05-01",
  "estimatedEndDate": "2026-06-15",
  "actualStartDate": null,
  "actualEndDate": null,
  "estimatedBudget": 185000.00,
  "actualCost": null,
  "createdAt": "2026-04-03T10:15:00",
  "updatedAt": "2026-04-03T10:15:00"
}
```

#### Validation Error Example

```json
{
  "timestamp": "2026-04-03T10:16:00",
  "status": 400,
  "error": "Bad Request",
  "message": "Validation failed",
  "validationErrors": [
    {
      "field": "estimatedEndDate",
      "rejectedValue": "2026-04-01",
      "message": "estimatedEndDate must be on or after estimatedStartDate"
    }
  ]
}
```

---

## Integration with Existing CustomerDetailResponse

The existing `GET /api/customers/{customerId}/detail` endpoint returns a `CustomerDetailResponse` that includes notes, contacts, and sales persons. This should be extended to also include a summary of projects:

```java
List<ProjectResponse> projects   // added to CustomerDetailResponse
```

This gives the full CRM aggregate view in a single call.

Implementation refinement:

- Treat the `projects` collection in `CustomerDetailResponse` as project summaries only.
- Do not include milestone or note collections in `CustomerDetailResponse`.
- If the team later needs a smaller payload, introduce a dedicated `ProjectSummaryResponse` record and use that here instead of the full `ProjectResponse`.

---

## Seed Data

Add to `fantaco-customer-main/src/main/resources/data.sql`:

### Projects (5 sample projects across existing customers)

| customer_id | project_name | pod_theme | status | site_address |
|-------------|-------------|-----------|--------|--------------|
| CUST003 | Tech Solutions IT — Interstellar Ops Center | INTERSTELLAR_SPACESHIP | IN_PROGRESS | 789 Pine Street, 4th Floor, San Francisco, CA 94101 |
| CUST006 | Creative Design Co — Speakeasy Studio | SPEAKEASY_1920S | PROPOSAL | 987 Cedar Lane, Suite 200, Chicago, IL 60601 |
| CUST010 | Handcrafted Furniture — Zen Showroom | ZEN_GARDEN | COMPLETED | 741 Ash Street, Building B, Nashville, TN 37201 |
| CUST001 | Brew & Bean — Enchanted Forest Lounge | ENCHANTED_FOREST | APPROVED | 123 Main Street, 2nd Floor, Portland, OR 97201 |
| CUST011 | Mind & Body Wellness — Custom Meditation Suite | CUSTOM | IN_PROGRESS | 852 Sage Circle, Unit 3, Boulder, CO 80301 |

Seed-data requirements:

- The final spec implementation should include explicit insert-ready rows, not just narrative examples.
- Seed data must define concrete values for:
  - project IDs or deterministic insert order
  - estimated and actual dates where applicable
  - estimated budgets and actual costs
  - milestone `sort_order`, `status`, and optional `completed_date`
  - note text, note type, author, and project association
- If `data.sql` cannot safely rely on generated IDs in the target database, replace it with deterministic startup seeding logic in application code.

### Milestones (standard 5-phase template per project, status varying by project status)

1. **Site Assessment & Measurements** — On-site survey, structural evaluation
2. **Theme Design & Customer Approval** — Design mockups, material selection, sign-off
3. **Construction & Structural Work** — Walls, flooring, electrical, plumbing
4. **Fixture & Technology Installation** — Theme-specific fixtures, AV, lighting, smart systems
5. **Final Walkthrough & Handoff** — Punch list, customer acceptance, warranty briefing

### Project Notes (2-3 per active project)

Realistic entries: site visit observations, change order for upgraded sound system, status update on material delivery, etc.

Recommended deterministic pattern:

- `PROPOSAL` projects: milestones mostly `NOT_STARTED`, no actual dates, 1 planning note.
- `APPROVED` projects: first milestone `COMPLETED`, later milestones `NOT_STARTED`, no actual end date.
- `IN_PROGRESS` projects: first milestones `COMPLETED`, active milestone `IN_PROGRESS`, at least 2 notes.
- `COMPLETED` projects: all milestones `COMPLETED`, actual dates and actual cost populated, final handoff note.

---

## MCP Server Extension

Add the following tools to `fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py`:

Current-state note:

- The existing customer MCP server is explicitly read-only today.
- Adding `update_project_status`, `add_project_note`, and `update_milestone_status` requires intentionally changing that contract from read-only to mixed read/write.
- If preserving read-only behavior is important, split write operations into a separate MCP server instead.

| Tool | Description | HTTP Call |
|------|-------------|----------|
| `get_customer_projects` | List all Imagination Pod projects for a customer | `GET /api/customers/{customerId}/projects` |
| `get_project_detail` | Retrieve a project with milestones and notes | `GET /api/customers/{customerId}/projects/{projectId}` |
| `search_projects_by_status` | Find all projects in a given status across a customer | `GET /api/customers/{customerId}/projects?status={status}` |
| `update_project_status` | Change a project's status (e.g. APPROVED → IN_PROGRESS) | `PUT /api/customers/{customerId}/projects/{projectId}` |
| `add_project_note` | Add a note to a project | `POST /api/customers/{customerId}/projects/{projectId}/notes` |
| `update_milestone_status` | Update a milestone's status and dates | `PUT .../milestones/{milestoneId}` |

### MCP Tool Schemas

| Tool | Required Inputs | Optional Inputs | Output |
|------|-----------------|-----------------|--------|
| `get_customer_projects` | `customer_id` | `status`, `pod_theme` | Wrapped list response under `results` |
| `get_project_detail` | `customer_id`, `project_id` | — | Raw project detail object |
| `search_projects_by_status` | `customer_id`, `status` | — | Wrapped list response under `results` |
| `update_project_status` | `customer_id`, `project_id`, `status` | `actual_start_date`, `actual_end_date`, `actual_cost` | Updated project object |
| `add_project_note` | `customer_id`, `project_id`, `note_text`, `note_type` | `author` | Created note object |
| `update_milestone_status` | `customer_id`, `project_id`, `milestone_id`, `status` | `completed_date`, `notes`, `due_date` | Updated milestone object |

MCP output convention:

- Continue using the current MCP server pattern where list responses are wrapped as `{ "results": [...] }`.
- Error payloads should pass through the API error body along with `status_code`.

---

## Files to Create / Modify

### New Files (in `fantaco-customer-main/src/main/java/com/customer/`)

```
model/
├── Project.java
├── ProjectMilestone.java
├── ProjectNote.java
├── PodTheme.java              (enum)
├── ProjectStatus.java         (enum)
├── MilestoneStatus.java       (enum)
└── ProjectNoteType.java       (enum)

dto/
├── ProjectRequest.java
├── ProjectUpdateRequest.java
├── ProjectResponse.java
├── ProjectDetailResponse.java
├── MilestoneRequest.java
├── MilestoneUpdateRequest.java
├── MilestoneResponse.java
├── ProjectNoteRequest.java
└── ProjectNoteResponse.java

repository/
├── ProjectRepository.java
├── ProjectMilestoneRepository.java
└── ProjectNoteRepository.java

service/
├── ProjectService.java
├── ProjectMilestoneService.java
└── ProjectNoteService.java

controller/
├── ProjectController.java
├── ProjectMilestoneController.java
└── ProjectNoteController.java

exception/
└── ProjectNotFoundException.java
```

### Modified Files

| File | Change |
|------|--------|
| `model/Customer.java` | Add `@OneToMany` to `Project` with cascade ALL + orphanRemoval |
| `dto/CustomerDetailResponse.java` | Add `List<ProjectResponse> projects` |
| `service/CustomerService.java` | Include projects in `getCustomerDetailById` mapping |
| `resources/data.sql` | Append project, milestone, and note seed data |
| `fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py` | Add 6 new MCP tools |

### Additional Files Expected

```
src/test/java/com/customer/service/
├── ProjectServiceTest.java
├── ProjectMilestoneServiceTest.java
└── ProjectNoteServiceTest.java

src/test/java/com/customer/controller/
├── ProjectControllerTest.java
├── ProjectMilestoneControllerTest.java
└── ProjectNoteControllerTest.java
```

If the project currently has no test pattern, these may be introduced incrementally, but the acceptance criteria below assume at least targeted service and controller coverage.

---

## Conventions Checklist

- [ ] DTOs are Java Records
- [ ] `@CrossOrigin(origins = "*")` on new controllers
- [ ] `@CreationTimestamp` and `@UpdateTimestamp` for audit fields
- [ ] `GlobalExceptionHandler` handles `ProjectNotFoundException`
- [ ] OpenAPI annotations on every endpoint
- [ ] Constructor injection (not `@Autowired`)
- [ ] `@Transactional(readOnly = true)` on read methods
- [ ] Logger in controllers
- [ ] Enums stored as Strings with `@Enumerated(EnumType.STRING)`
- [ ] Ownership validation: project belongs to customer, milestone belongs to project, note belongs to project
- [ ] Cascade ALL + orphanRemoval on parent → child relationships
- [ ] `@JsonIgnore` on child → parent back-references

---

## Definition of Done

- Project, milestone, and project-note entities are persisted and accessible through the documented REST endpoints.
- All new endpoints appear in generated OpenAPI docs with example payloads.
- Ownership validation returns `404` for mismatched nested resources.
- Invalid status transitions return `409`.
- Milestone ordering is deterministic and enforced.
- `GET /api/customers/{customerId}/detail` includes project summaries.
- Seed data loads successfully in a clean local environment.
- MCP tools are implemented and aligned with the final REST contracts.
- Automated tests cover:
  - create/read/update/delete happy paths
  - validation failures
  - ownership mismatch
  - invalid status transition
  - milestone ordering conflict
