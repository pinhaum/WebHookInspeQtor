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
| Deletion | Delete bins with `expires_at <= now`; requests go through `on_delete: :delete_all` | One statement, the database does the cascade | y |
| Clock | `now` is the app clock (`DateTime.utc_now(:second)`), as in `Inspector.fetch_live_bin/2` | Read path and prune agree on the boundary: a bin is live exactly while `expires_at > now` | n |
| Oban install | Oban is added by this feature (dep, `oban_jobs` migration, supervision, `testing: :manual` in test) | Foundation never installed it; retention is its first user | n |
| Oban job history | `Oban.Pruner` (`pruner: [max_age: {7, :days}]`; `Oban.Plugins.Pruner` is deprecated in 2.24) | Bounded-storage goal applies to `oban_jobs` too; a week of history covers debugging a failed run | n |
| Index | Index on `bins.expires_at` | bin-creation design deferred it to this feature; keeps the hourly delete off a sequential scan | n |
| Oban child options under test | `start/2` passes `Application.fetch_env!(:whiq, Oban)` unchanged; tests assert that env normalized by `Oban.Config.new/1` plus that Oban runs on `Whiq.Repo`. A mutant that edits the options inside `start/2` (M13) is accepted as undetectable under `testing: :manual` | `testing: :manual` strips plugins from the running config; a seam only for tests adds structure without behavior | n |
| Open bin page when its bin is pruned | Nothing happens until the next navigation, which 404s | Already out of scope in live-inspection | y |
| Prune racing a capture | Delete waits on the capture's `FOR UPDATE` row lock; a capture that loses the race gets `:not_found` | Accepted in abuse-limits design | y |
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
5. WHEN the prune job finishes THEN the system SHALL log the number of deleted bins at info level (RET-06)
6. The system SHALL prune finished Oban job rows older than 7 days (RET-07)

**Independent Test**: Insert one expired and one live bin with requests, perform the job, assert only the live bin and its requests remain.

---

## Edge Cases

- WHEN the prune job runs with no expired bins THEN the system SHALL complete successfully and delete nothing (RET-05)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| RET-01 | P1: Prune expired bins | Execute | Implementing |
| RET-02 | P1: Prune expired bins | Execute | Implementing |
| RET-03 | P1: Prune expired bins | Execute | Implementing |
| RET-04 | P1: Prune expired bins | Execute | Implementing |
| RET-05 | P1: Prune expired bins | Execute | Implementing |
| RET-06 | P1: Prune expired bins | Execute | Implementing |
| RET-07 | P1: Prune expired bins | Execute | Implementing |

**Coverage:** 7 total, 7 implemented (inline plan, no tasks.md)

---

## Success Criteria

- [ ] The worker is covered by tests using `Oban.Testing`; the cron entry and the pruner are asserted in config.
