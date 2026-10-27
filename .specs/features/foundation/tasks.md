# Foundation Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: skipped - architecture decisions are AD-001 and AD-002 in `.specs/STATE.md`
**Status**: In Progress

---

## Test Coverage Matrix

> Generated from spec - confirm before Execute. Guidelines found: none - strong defaults applied. No tests exist yet; test types and commands come from the spec (FND-09, FND-10).

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Endpoint / router / controller | integration (`Phoenix.ConnTest`) | Every FND AC of the capture pipeline: one test per AC, asserting the spec outcome on the returned conn | `test/whiq_web/**/*_test.exs` | `docker compose run --rm app mix test` |
| Dev environment (Dockerfile, compose, config) | none | - (smoke commands from FND-08, FND-09, FND-11 in the task gate) | - | build gate + smoke commands |

## Gate Check Commands

> Generated from spec - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | Not used (no unit-only layer) | - |
| Full | Tasks with ConnTest tests | `docker compose run --rm app mix test` |
| Build | Last task of a phase, or infra-only tasks | `docker compose run --rm app mix precommit` |

---

## Execution Plan

Phases run sequentially; tasks run in order within a phase.

### Phase 1: Dev environment

```
T1 → T2
```

### Phase 2: Capture pipeline

```
T3 → T4
```

---

## Task Breakdown

### T1: Create the dev container image and compose stack

**What**: `Dockerfile.dev` (elixir:1.19.6-otp-28, inotify-tools, hex, rebar, phx_new 1.8.16 under a world-writable `MIX_HOME`) and `compose.yaml` (`app` running as `${UID}:${GID}` with `HOME=/tmp`, project bind-mounted at `/app`, port 4000; `db` on postgres:17 with a healthcheck).
**Where**: `Dockerfile.dev`, `compose.yaml`, `.env.example`
**Depends on**: None
**Reuses**: bind-mount findings in `spec.md` Assumptions
**Requirement**: FND-11

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] `docker compose build` succeeds
- [x] `docker compose run --rm app mix phx.new --version` prints `Phoenix installer v1.8.16`
- [x] `docker compose run --rm app touch probe` creates a file owned by the host UID/GID (FND-11), then it is removed

**Tests**: none
**Gate**: build (smoke commands above; `mix precommit` does not exist yet)

**Commit**: `build(dev): add containerized dev environment`

---

### T2: Generate the Phoenix app inside the container

**What**: Run `mix phx.new . --app whiq` (keeping the existing `README.md`), point Repo hostname to `db` through `DATABASE_HOST`, bind the dev endpoint to `0.0.0.0`, set the compose `app` command to `mix setup && mix phx.server`, and ignore `.env`.
**Where**: generated tree; `config/dev.exs`, `config/test.exs`, `compose.yaml`, `.gitignore` (modify)
**Depends on**: T1
**Reuses**: phx_new 1.8.16 generator output
**Requirement**: FND-08, FND-09, FND-10, FND-11

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] `docker compose up` on a clean tree serves `http://localhost:4000` with status 200 and code reloading enabled (FND-08)
- [x] `docker compose run --rm app mix test` passes against the compose Postgres (FND-09)
- [x] `docker compose run --rm app mix precommit` passes (FND-10)
- [x] `find . -path ./.git -prune -o ! -user $(id -u) -print` prints nothing (FND-11)
- [x] Test count: generated suite passes, none skipped

**Tests**: none
**Gate**: build

**Commit**: `feat(foundation): generate phoenix 1.8 app`

---

### T3: Strip request-altering plugs from the endpoint

**What**: Remove `Plug.Parsers` and `Plug.MethodOverride` from the endpoint, move an `:urlencoded` parser into the `:browser` pipeline, remove the `:api` pipeline, and replace `Plug.Head` with a function plug that skips paths under `/h/` (AD-001, AD-002).
**Where**: `lib/whiq_web/endpoint.ex`, `lib/whiq_web/router.ex` (modify)
**Depends on**: None
**Reuses**: Phoenix generated endpoint and router
**Requirement**: FND-06

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] HEAD `/` responds 200 with an empty body (FND-06), asserted in `test/whiq_web/controllers/page_controller_test.exs`
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: generated suite + 1, none skipped

**Tests**: integration
**Gate**: full

**Commit**: `feat(foundation): keep request-altering plugs off the capture path`

---

### T4: Add the capture route and stub controller

**What**: A `:capture` pipeline with no plugs, `match :*` routes for `/h/:token` and `/h/:token/*path`, and `WhiqWeb.CaptureController` responding 200 with an empty body.
**Where**: `lib/whiq_web/controllers/capture_controller.ex` (new), `lib/whiq_web/router.ex` (modify)
**Depends on**: T3
**Reuses**: Phoenix controller conventions
**Requirement**: FND-01, FND-02, FND-03, FND-04, FND-05, FND-07

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `test/whiq_web/controllers/capture_controller_test.exs` has one test per AC, each asserting `conn.private.phoenix_controller == WhiqWeb.CaptureController` plus:
  - FND-01: `conn.body_params` is `%Plug.Conn.Unfetched{}` and `Plug.Conn.read_body(conn)` returns the full body sent
  - FND-02: HEAD keeps `conn.method == "HEAD"`
  - FND-03: POST with `_method=DELETE` keeps `conn.method == "POST"`
  - FND-04: `/h/:token/any/sub/path` dispatches to the controller
  - FND-05: `PROPFIND` dispatches with `conn.method == "PROPFIND"`
  - FND-07: `Accept: application/xml` gets status 200
- [ ] Gate check passes: `docker compose run --rm app mix precommit`
- [ ] Test count: previous suite + 6, none skipped

**Tests**: integration
**Gate**: build

**Commit**: `feat(foundation): add capture route with stub controller`

---

## Phase Execution Map

```
Phase 1 → Phase 2

Phase 1:  T1 ------→ T2
Phase 2:  T3 ------→ T4
```

Phase 2 depends on Phase 1 as a whole (the app must exist), so T3 has no intra-phase dependency.

---

## Validation

### Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: Dev image + compose | One environment; the three files are useless apart | ⚠️ Cohesive, kept together |
| T2: Generate app | One generator run plus the config it needs to boot in compose | ⚠️ Cohesive, kept together |
| T3: Endpoint plugs | Endpoint plus the router pipeline that receives the moved parser | ⚠️ Cohesive, kept together |
| T4: Capture route + controller | One endpoint | ✅ Granular |

### Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | None | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | None (Phase 1) | None | ✅ Match |
| T4 | T3 | T3 → T4 | ✅ Match |

### Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Dev environment | none | none | ✅ OK |
| T2 | Dev environment + generated app (ships its own tests) | none | none | ✅ OK |
| T3 | Endpoint / router | integration | integration | ✅ OK |
| T4 | Router / controller | integration | integration | ✅ OK |
