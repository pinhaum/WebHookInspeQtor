# Delivery Specification

## Problem Statement

A portfolio project is judged by its public face: a live URL, green CI and a README that explains the reasoning. The app needs a production release image, an automated check pipeline, a deploy to Fly.io and documentation of the decisions made along the way.

## Goals

- [ ] Every push to `main` and every pull request runs the full check suite.
- [ ] The app is deploy-ready for Fly.io: a release image that migrates on start and a `fly.toml`. A live deploy is out of scope.
- [ ] The README lets a reviewer understand the design in five minutes.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Automatic deploy from CI | Deploys are manual; no deploy credentials in CI for a portfolio repo |
| Multi-region or clustering | Single machine is enough; rate limiter, PubSub and Oban cron assume one live node |
| Managed database (backups, HA) | Bin data is ephemeral (7 days); legacy Fly Postgres is enough |
| Monitoring beyond Fly's built-in metrics | Scope |
| Live production deploy (retires DEL-05, DEL-06, DEL-07, DEL-12) | Study project. Fly has no free plan for new accounts, and a trial machine stops after 5 minutes (observed 2026-10-30, the Postgres machine stopped before the first `release_command`). The release image and `fly.toml` stay as deploy-ready artefacts |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Host | Fly.io app + legacy (unmanaged) Fly Postgres via `fly postgres create` if it still creates new clusters; otherwise Fly Managed Postgres (`fly mpg create`). Decided at deploy time | User choice; legacy is cheapest and 7-day data needs no managed backups. Fly forum reports the legacy commands as deprecated (not confirmed in official docs). The app only reads `DATABASE_URL`, so either works | y |
| Topology | Exactly one app machine, always on: `min_machines_running = 1`, auto-stop disabled | Hammer ETS limiter and Phoenix PubSub are per node, and the hourly retention cron only runs while a node is up | y |
| Release image | `mix phx.gen.release --docker` output | Official generator | y |
| Migrations | Fly `release_command` runs the release migrate script | Runs before new machines take traffic | y |
| HTTPS | Fly proxy forces HTTPS; plain-HTTP captures get redirected and are not stored | Senders almost always use HTTPS; avoids storing secrets sent in clear | y |
| LiveDashboard in prod | Not exposed | It sits behind `dev_routes` in the generated router | y |
| CI | GitHub Actions with a Postgres service container | Repository host | y |
| CI checks | `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, `mix test` | Same as `mix precommit`, but non-mutating | y |
| CI image build | A separate CI job builds the release Docker image without pushing it | Catches Dockerfile and asset breakage before a manual `fly deploy` | y |
| README language | English | User choice | y |
| Failed `release_command` (formerly DEL-10) | Documented as Fly behavior in the README: a failing migration aborts the deploy and the previous release keeps serving; not tested | Testing it means deploying a broken migration to production on purpose | y |
| Client IP in prod (DEL-06) | Already implemented by `WhiqWeb.ClientIP` and `config/runtime.exs`; delivery only verifies it live | Shipped with request-capture (commit `5f3f696`) | y |
| Health check vs `force_ssl` | Fly's HTTP health check must not be redirected; the exact mechanism (excluded path or forwarded-proto header) is a Design choice | `force_ssl` in `config/prod.exs` redirects any request without `x-forwarded-proto: https` | n |
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
3. WHEN a commit is pushed to `main` or a pull request is opened THEN CI SHALL build the release Docker image without pushing it (DEL-11)

**Independent Test**: Push a branch with a formatting error and see the run fail.

---

### P1: Deploy readiness ⭐ MVP

**User Story**: As a reviewer, I want the project to ship a production release so that I can see it is deployable without it running live.

**Why P1**: A release that migrates and redirects correctly is the deployable core; running it live is out of scope.

**Acceptance Criteria**:

1. WHEN the release image runs `/app/bin/migrate` against an empty database THEN it SHALL apply every pending migration and exit 0 (DEL-03)
2. WHEN a plain-HTTP request with a non-local host reaches the endpoint under the prod config THEN the system SHALL redirect it to HTTPS (DEL-04)

DEL-05, DEL-06, DEL-07 and DEL-12 are retired with the live deploy (see Out of Scope).

**Independent Test**: Build the release image and run its migrate script against a fresh compose database.

---

### P1: Reviewer-facing README ⭐ MVP

**User Story**: As a reviewer, I want a README that explains what the project does and why it is built this way so that I can evaluate the reasoning.

**Why P1**: Reviewers read the README first.

**Acceptance Criteria**:

1. The README SHALL state that the app is deploy-ready but not deployed, and contain local setup with `docker compose`, an architecture overview and a "Decisions" section derived from `.specs/STATE.md` (DEL-08)
2. The README SHALL document the known fidelity limits: lowercased header names and plain-HTTP captures being redirected (DEL-09)

**Independent Test**: A reader follows the setup section on a clean machine with only Docker.

---

## Edge Cases

- WHEN Fly's health check probes the app over the internal HTTP port THEN the system SHALL answer 200 instead of redirecting (DEL-13)

---

## Implicit-Requirement Sweep

| Dimension | Resolution |
| --------- | ---------- |
| Input validation & bounds | N/A because capture limits belong to abuse-limits; delivery adds no input |
| Failure / partial-failure states | DEL-02 (failed CI run); failed migration is the "Failed `release_command`" assumption |
| Idempotency / retry | N/A because deploys are manual and the release migrate script is idempotent (Ecto skips applied migrations) |
| Auth boundaries & rate limits | LiveDashboard not exposed (assumption); forged `fly-client-ip` (DEL-07) is retired with the live deploy |
| Concurrency / ordering | `fly.toml` pins one always-on machine so PubSub and Oban cron see a single node (DEL-12 retired, config kept) |
| Data lifecycle / expiry | N/A because retention owns expiry |
| Observability | N/A because monitoring beyond Fly's built-in metrics is out of scope |
| External-dependency failure | DEL-13 (health check); Postgres outage behavior is unchanged from local and not re-specified |
| State-transition integrity | DEL-03 (migrations run before the new release serves) |

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| DEL-01 | P1: Continuous integration | T5, T10 | Done |
| DEL-02 | P1: Continuous integration | T5, T10 | Done |
| DEL-03 | P1: Deploy readiness | T1 | Done |
| DEL-04 | P1: Deploy readiness | T3 | Done |
| DEL-05 | (live deploy) | - | Retired |
| DEL-06 | (live deploy) | - | Retired |
| DEL-07 | (live deploy) | - | Retired |
| DEL-08 | P1: Reviewer-facing README | T7 | Done |
| DEL-09 | P1: Reviewer-facing README | T7 | Done |
| DEL-11 | P1: Continuous integration | T6, T10 | Done |
| DEL-12 | (live deploy) | T4 | Retired |
| DEL-13 | Edge case | T2, T3, T4 | Done |

DEL-10 is retired: it became the "Failed `release_command`" assumption. DEL-05, DEL-06, DEL-07 and DEL-12 are retired with the live deploy.

**Coverage:** 8 active, 8 mapped to tasks, 0 unmapped. 4 retired.

---

## Success Criteria

- [ ] CI badge green on `main`.
- [ ] ~~Live URL captures and displays a request end to end.~~ Retired with the live deploy (see Out of Scope).
