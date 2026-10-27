# Delivery Specification

## Problem Statement

A portfolio project is judged by its public face: a live URL, green CI and a README that explains the reasoning. The app needs a production release image, an automated check pipeline, a deploy to Fly.io and documentation of the decisions made along the way.

## Goals

- [ ] Every push to `main` and every pull request runs the full check suite.
- [ ] The app runs on Fly.io with a public HTTPS URL.
- [ ] The README lets a reviewer understand the design in five minutes.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Automatic deploy from CI | Deploys are manual; no deploy credentials in CI for a portfolio repo |
| Multi-region or clustering | Single machine is enough; rate limiter is per node |
| Monitoring beyond Fly's built-in metrics | Scope |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Host | Fly.io with Fly Postgres | User choice | y |
| Release image | `mix phx.gen.release --docker` output | Official generator | y |
| Migrations | Fly `release_command` runs the release migrate script | Runs before new machines take traffic | y |
| HTTPS | Fly proxy forces HTTPS; plain-HTTP captures get redirected and are not stored | Senders almost always use HTTPS; avoids storing secrets sent in clear | y |
| LiveDashboard in prod | Not exposed | It sits behind `dev_routes` in the generated router | y |
| CI | GitHub Actions with a Postgres service container | Repository host | y |
| CI checks | `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, `mix test` | Same as `mix precommit`, but non-mutating | y |
| README language | English | User choice | y |
| DEL-07 failure | Switch client IP resolution to `x-forwarded-for` parsed from the right with `remote_ip`, as a fix task | Plan B agreed before deploy (see `request-capture` assumptions) | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Continuous integration ⭐ MVP

**User Story**: As a reviewer, I want to see a green check on every commit so that I trust the code compiles and its tests pass.

**Why P1**: Baseline signal of quality.

**Acceptance Criteria**:

1. WHEN a commit is pushed to `main` or a pull request is opened THEN CI SHALL run the format, compile, unused-deps and test checks (DEL-01)
2. IF any check fails THEN CI SHALL mark the run as failed (DEL-02)

**Independent Test**: Push a branch with a formatting error and see the run fail.

---

### P1: Production deploy ⭐ MVP

**User Story**: As a reviewer, I want a live URL so that I can try the inspector without cloning it.

**Why P1**: A demo is worth more than a description.

**Acceptance Criteria**:

1. WHEN `fly deploy` runs THEN the system SHALL build the release image, run pending migrations and start serving (DEL-03)
2. WHEN a plain-HTTP request reaches the app's Fly hostname THEN the system SHALL redirect it to HTTPS (DEL-04)
3. WHEN a `curl` with a JSON body is sent to a capture URL in production THEN the system SHALL show it on the open bin page (DEL-05)
4. WHILE running in production the system SHALL read the client IP from the `fly-client-ip` header (DEL-06)
5. IF a production request carries a forged `fly-client-ip` header THEN the recorded `remote_ip` SHALL be the real client address (DEL-07)

**Independent Test**: Manual smoke test after deploy, recorded in `validation.md`.

---

### P1: Reviewer-facing README ⭐ MVP

**User Story**: As a reviewer, I want a README that explains what the project does and why it is built this way so that I can evaluate the reasoning.

**Why P1**: Reviewers read the README first.

**Acceptance Criteria**:

1. The README SHALL contain a live demo link, local setup with `docker compose`, an architecture overview and a "Decisions" section derived from `.specs/STATE.md` (DEL-08)
2. The README SHALL document the known fidelity limits: lowercased header names and plain-HTTP captures being redirected (DEL-09)

**Independent Test**: A reader follows the setup section on a clean machine with only Docker.

---

## Edge Cases

- IF the `release_command` migration fails THEN Fly SHALL keep the previous release serving (DEL-10)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| DEL-01 | P1: Continuous integration | - | Pending |
| DEL-02 | P1: Continuous integration | - | Pending |
| DEL-03 | P1: Production deploy | - | Pending |
| DEL-04 | P1: Production deploy | - | Pending |
| DEL-05 | P1: Production deploy | - | Pending |
| DEL-06 | P1: Production deploy | - | Pending |
| DEL-07 | P1: Production deploy | - | Pending |
| DEL-08 | P1: Reviewer-facing README | - | Pending |
| DEL-09 | P1: Reviewer-facing README | - | Pending |
| DEL-10 | P1: Production deploy | - | Pending |

**Coverage:** 10 total, 0 mapped to tasks, 10 unmapped ⚠️

---

## Success Criteria

- [ ] CI badge green on `main`.
- [ ] Live URL captures and displays a request end to end.
