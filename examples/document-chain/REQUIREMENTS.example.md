# REQUIREMENTS.md

## Scope

**Feature/milestone:** MVP — Core Task Management
**Target date:** End of Q2 2026
**Status:** In Progress

## Must Have

### User authentication
- **Description:** Email/password signup and login with session management
- **Acceptance criteria:**
  - [x] Users can sign up with email and password
  - [x] Users can log in and maintain a session
  - [x] Password reset via email link
  - [x] Sessions expire after 7 days of inactivity

### Task CRUD
- **Description:** Create, read, update, and delete tasks with core fields
- **Acceptance criteria:**
  - [x] Create tasks with title, description, assignee, priority, due date
  - [x] Edit any field on an existing task
  - [x] Delete tasks (soft delete with 30-day recovery)
  - [ ] Bulk actions (assign, move, delete) on selected tasks

### Board view
- **Description:** Kanban board with customizable columns representing task stages
- **Acceptance criteria:**
  - [x] Default columns: Backlog, To Do, In Progress, Review, Done
  - [ ] Drag-and-drop tasks between columns
  - [ ] Custom columns (add, rename, reorder, delete)
  - [ ] Column WIP limits with visual warning

### Team workspace
- **Description:** Shared workspace where team members collaborate on tasks
- **Acceptance criteria:**
  - [ ] Create workspace with name and invite link
  - [ ] Invite members by email
  - [ ] Role-based access: admin, member, viewer
  - [ ] Workspace settings (name, default columns, priorities)

## Should Have

### Real-time updates
- **Description:** Changes by one user appear for all team members without refresh
- **Acceptance criteria:**
  - [ ] Task moves and edits broadcast via SSE
  - [ ] Online presence indicators for team members
  - [ ] Optimistic UI updates with conflict resolution

### Smart prioritization
- **Description:** Auto-suggest task priority based on due date, dependencies, and workload
- **Acceptance criteria:**
  - [ ] Priority score calculated from due date proximity and blocked tasks
  - [ ] "What should I work on next?" suggestion per user
  - [ ] Priority changes surfaced as notifications

## Nice to Have

### Activity feed
- **Description:** Timeline of recent actions across the workspace
- **Acceptance criteria:**
  - [ ] Show task creates, moves, assignments, and comments
  - [ ] Filter by user or task
  - [ ] Grouped by day

## Out of Scope

- File attachments (defer to v1.1)
- Time tracking
- Sprint planning / velocity metrics
- External integrations (GitHub, Slack)

## Open Questions

- [ ] Should deleted tasks be recoverable by any member or only admins?
- [ ] Do we need task templates for recurring work patterns?