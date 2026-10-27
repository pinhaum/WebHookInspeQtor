# Retention Specification

## Problem Statement

Bins expire 7 days after creation, but expiry only matters if expired data is actually removed. A scheduled job must delete expired bins and their requests so storage stays bounded over time.

## Goals

- [ ] No bin survives more than about one hour past its `expires_at`.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Extending a bin's TTL | Fixed TTL (user choice) |
| Archiving expired data | Debug data has no value after expiry |
| Notifying owners before expiry | No accounts (AD-003) |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Scheduler | Oban cron plugin, hourly | Project requirement; survives restarts, has retries | y |
| Deletion | Delete bins with `expires_at <= now()`; requests go through `on_delete: :delete_all` | One statement, the database does the cascade | y |
| Batching | Single delete, no batching | Worst case is about one day of bins; small | y |
| Failure handling | Oban default retries | A failed run is retried; the next hourly run also covers it | y |
| Read path before pruning | Expired bins already return 404 (BIN-10, CAP-17) | Pruning is storage hygiene, not access control | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Prune expired bins ⭐ MVP

**User Story**: As the operator, I want expired bins removed automatically so that storage does not grow without bound.

**Why P1**: Without it the TTL is cosmetic.

**Acceptance Criteria**:

1. WHEN the prune job runs THEN the system SHALL delete every bin whose `expires_at` is at or before the current time (RET-01)
2. WHEN the prune job deletes a bin THEN the system SHALL delete all of its captured requests (RET-02)
3. WHEN the prune job runs THEN the system SHALL keep every bin whose `expires_at` is after the current time (RET-03)
4. The system SHALL schedule the prune job once per hour (RET-04)

**Independent Test**: Insert one expired and one live bin with requests, perform the job, assert only the live bin and its requests remain.

---

## Edge Cases

- WHEN the prune job runs with no expired bins THEN the system SHALL complete successfully and delete nothing (RET-05)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| RET-01 | P1: Prune expired bins | - | Pending |
| RET-02 | P1: Prune expired bins | - | Pending |
| RET-03 | P1: Prune expired bins | - | Pending |
| RET-04 | P1: Prune expired bins | - | Pending |
| RET-05 | P1: Prune expired bins | - | Pending |

**Coverage:** 5 total, 0 mapped to tasks, 5 unmapped ⚠️

---

## Success Criteria

- [ ] The worker is covered by tests using `Oban.Testing` and the cron entry is asserted in config.
