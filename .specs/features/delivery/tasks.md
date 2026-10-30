# Delivery Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/delivery/design.md`
**Status**: Approved

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec - confirm before Execute. Guidelines found: `AGENTS.md` (ConnTest + `LazyHTML`, assert on ids, `mix precommit` at the end). Floor: `test/whiq_web/controllers/page_controller_test.exs`, `test/whiq_web/client_ip_test.exs`. Infra layers (Dockerfile, `fly.toml`, workflow, README) have no ExUnit surface; their gate is a local command that exercises them (image build, `actionlint`, non-mutating check commands). The ACs that need the live deploy or GitHub are verified in Phase 4 and recorded in `smoke.md`.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Controller / router (`/health`) | integration (`ConnTest`) | DEL-13 app side: 200, `text/plain`, body `ok`, no DB access, no session cookie | `test/whiq_web/controllers/health_controller_test.exs` | `docker compose run --rm -T app mix test test/whiq_web/controllers/health_controller_test.exs` |
| Prod endpoint config (`force_ssl`) | unit (`ExUnit.Case`) | `config/prod.exs` read with `Config.Reader`, fed to `Plug.SSL`: plain-HTTP `/health` passes through, plain-HTTP `/` and `/h/x` get 301 to https, `x-forwarded-proto: https` passes | `test/whiq_web/prod_force_ssl_test.exs` | `docker compose run --rm -T app mix test test/whiq_web/prod_force_ssl_test.exs` |
| Release image (`Dockerfile`, `rel/`, `Whiq.Release`) | none (build gate) | Image builds; `bin/migrate` against compose `db` applies all migrations and exits 0 | `Dockerfile`, `rel/overlays/bin/` | `docker build -t whiq:release .` |
| `fly.toml` / workflow / README | none | Build gate; workflow linted with `actionlint` | - | see Gate Check Commands |
| Live deploy and CI | manual smoke | DEL-01..07, DEL-11..13 live, evidence in `smoke.md` | `.specs/features/delivery/smoke.md` | `curl`, `fly`, `gh` (Phase 4) |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | Single test-file tasks | `docker compose run --rm -T app mix test <task test file>` |
| Full | Router / endpoint changes | `docker compose run --rm -T app mix test` |
| Build | Last task of a phase, generated or config-only tasks | `docker compose run --rm -T app mix precommit` (plus `docker build -t whiq:release .` for T1 and T4, `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest` for T5 and T6) |

---

## Execution Plan

Phases run sequentially; tasks run in order within a phase.

### Phase 1: Release and app code

```
T1 → T2 → T3 → T4
```

### Phase 2: Continuous integration

```
T5 → T6
```

### Phase 3: README

```
T7
```

### Phase 4: Live verification (outward-facing, explicit go-ahead per step)

```
T8 → T9 → T10
```

---

## Task Breakdown

### T1: Generate the release files

**What**: Run `mix phx.gen.release --docker` and keep its output unchanged: `Dockerfile`, `.dockerignore`, `rel/overlays/bin/{server,migrate}` (plus `.bat`), `lib/whiq/release.ex`. Pin the builder to an existing `hexpm/elixir` tag for Elixir 1.19.6 / OTP 28 if the generated tag does not resolve.
**Where**: `Dockerfile` (generated, with its siblings)
**Depends on**: None
**Reuses**: `deps/phoenix/priv/templates/phx.gen.release/`
**Requirement**: DEL-03

**Tools**:

- MCP: NONE
- Skill: `ecc:docker-patterns`

**Done when**:

- [x] `docker build -t whiq:release .` succeeds
- [x] `bin/migrate` in the image, pointed at the compose `db` on a fresh database, exits 0 and leaves all 5 migrations applied, `oban_jobs` included
- [x] Gate check passes: `docker compose run --rm -T app mix precommit`
- [x] Test count: baseline passes unchanged

**Tests**: none
**Gate**: build

**Commit**: `build(release): add phx.gen.release docker release`

---

### T2: Add the /health endpoint

**What**: `WhiqWeb.HealthController.show/2` answers `200 text/plain "ok"`. It is routed as `get "/health"` in a scope without a pipeline, so no session and no body parsing.
**Where**: `lib/whiq_web/controllers/health_controller.ex` (new; plus its one route line)
**Depends on**: T1
**Reuses**: `/h` scope pattern in `lib/whiq_web/router.ex:23`
**Requirement**: DEL-13

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] `GET /health` → status 200, `content-type` starts with `text/plain`, body `ok`
- [x] Response carries no `set-cookie` (no `:browser` pipeline)
- [x] Gate check passes: `docker compose run --rm -T app mix test`
- [x] Test count: baseline + new tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(web): add health endpoint for the fly check`

---

### T3: Exclude /health from force_ssl

**What**: Add `paths: ["/health"]` to `force_ssl` `exclude` in `config/prod.exs`, keeping `hosts: ["localhost", "127.0.0.1"]`. Add a test that reads `config/prod.exs` via `Config.Reader.read!/1` and runs `Plug.SSL` with those exact options.
**Where**: `config/prod.exs` (modify)
**Depends on**: T2
**Reuses**: `Plug.SSL` exclude option (`deps/plug/lib/plug/ssl.ex:66`)
**Requirement**: DEL-13, DEL-04 (app layer)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] Plain-HTTP `GET /health` with a non-local host is not halted
- [x] Plain-HTTP `GET /` (301) and `POST /h/abc` (307, `Plug.SSL` keeps the method for non-GET/HEAD) with a non-local host are halted with a `location` starting `https://`
- [x] `GET /` with `x-forwarded-proto: https` is not halted
- [x] Gate check passes: `docker compose run --rm -T app mix precommit`
- [x] Test count: previous + new tests pass

**Tests**: unit
**Gate**: build

**Commit**: `fix(config): let the health check bypass force_ssl`

---

### T4: Add fly.toml

**What**: `fly.toml` for app `whiq`:
- `primary_region = "gru"`
- `[deploy] release_command = "/app/bin/migrate"`
- `[env]`: `PHX_HOST = "whiq.fly.dev"`, `PORT = "8080"`, `ECTO_IPV6 = "true"`, `ERL_AFLAGS = "-proto_dist inet6_tcp"`
- `[http_service]`: `internal_port = 8080`, `force_https = true`, `auto_stop_machines = "off"`, `auto_start_machines = true`, `min_machines_running = 1`
- `[[http_service.checks]]`: `GET /health`
- `[[vm]]`: shared-cpu-1x

**Where**: `fly.toml` (new)
**Depends on**: T3
**Reuses**: key names verified in https://docs.fly.io/reference/configuration
**Requirement**: DEL-03, DEL-04, DEL-12, DEL-13

**Tools**:

- MCP: NONE
- Skill: `ecc:deployment-patterns`

**Done when**:

- [x] Every key above is present with the stated value
- [x] `.dockerignore` does not exclude anything the image needs; `fly.toml` itself excluded or harmless
- [x] Gate check passes: `docker compose run --rm -T app mix precommit` and `docker build -t whiq:release .`
- [x] Test count: baseline passes unchanged

**Tests**: none
**Gate**: build

**Commit**: `build(fly): add single-machine fly config`

---

### T5: Add the CI checks job

**What**: `.github/workflows/ci.yml` on `push` to `main` and `pull_request`, job `checks`:
- `erlef/setup-beam@v1` with `version-type: strict`; Elixir/OTP equal to the `Dockerfile.dev` image (exact OTP read from that image)
- `actions/cache` on `deps` and `_build`, keyed by the `mix.lock` hash and the versions
- service `postgres:17` with `pg_isready` health options; `MIX_ENV=test`
- steps: `mix deps.get`, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, `mix test`

**Where**: `.github/workflows/ci.yml` (new)
**Depends on**: None (runs after Phase 1)
**Reuses**: check list from `mix.exs:100` (`precommit`), DB defaults in `config/test.exs:9-11`
**Requirement**: DEL-01, DEL-02

**Tools**:

- MCP: NONE
- Skill: `ecc:github-ops`

**Done when**:

- [x] `actionlint` reports no errors
- [x] The same five commands pass locally in the compose `app` container with `MIX_ENV=test`
- [x] Gate check passes: `docker compose run --rm -T app mix precommit`
- [x] Test count: baseline passes unchanged

**Tests**: none
**Gate**: build

**Commit**: `ci: run format, compile, unused-deps and test checks`

---

### T6: Add the release-image CI job

**What**: Job `release-image` in the same workflow: `docker/setup-buildx-action@v4` + `docker/build-push-action@v7`, `push: false`, `cache-from: type=gha`, `cache-to: type=gha,mode=max`.
**Where**: `.github/workflows/ci.yml` (modify)
**Depends on**: T5
**Reuses**: `Dockerfile` from T1
**Requirement**: DEL-11

**Tools**:

- MCP: NONE
- Skill: `ecc:github-ops`

**Done when**:

- [x] `actionlint` reports no errors
- [x] Job never pushes (`push: false`, no registry login step)
- [x] Gate check passes: `docker compose run --rm -T app mix precommit`
- [x] Test count: baseline passes unchanged

**Tests**: none
**Gate**: build

**Commit**: `ci: build the release image without pushing`

---

### T7: Write the reviewer-facing README

**What**: Replace `README.md` with these sections:
- tagline, CI badge (`ci.yml`) and the live link `https://whiq.fly.dev`
- what it does
- local setup: `cp .env.example .env`, fill in UID/GID, `docker compose up`
- architecture overview: Inspector context, capture path, LiveView + PubSub, Oban retention, single node
- Decisions: one short entry per active AD-001..AD-008, plus the single-machine and failed-`release_command` assumptions
- known fidelity limits: lowercased header names, and plain-HTTP captures being redirected and not stored

**Where**: `README.md` (modify)
**Depends on**: None (runs after Phase 2)
**Reuses**: `.specs/STATE.md` Decisions, `compose.yaml`, `.env.example`
**Requirement**: DEL-08, DEL-09

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Every section above present; each AD-001..AD-008 represented
- [ ] Both fidelity limits stated explicitly
- [ ] Setup commands match `compose.yaml` and `.env.example` exactly
- [ ] Gate check passes: `docker compose run --rm -T app mix precommit`
- [ ] Test count: baseline passes unchanged

**Tests**: none
**Gate**: build

**Commit**: `docs(readme): add reviewer-facing readme with decisions`

---

### T8: Provision and deploy (outward-facing)

**What**: With the user's go-ahead and Fly login:
- `fly apps create whiq` (fallback `whiq-inspector`, updating `fly.toml`, `PHX_HOST` and README)
- `fly postgres create` + `attach`; fallback `fly mpg create` + `attach`; confirm `DATABASE_URL` is set
- `fly secrets set SECRET_KEY_BASE=...`
- `fly deploy --ha=false`

Record the commands and their outputs, with no secret values, in `smoke.md`.
**Where**: `.specs/features/delivery/smoke.md` (new)
**Depends on**: None (runs after Phase 3)
**Reuses**: `fly.toml` from T4
**Requirement**: DEL-03, DEL-12, DEL-13

**Tools**:

- MCP: NONE
- Skill: `ecc:deployment-patterns`, `superpowers:verification-before-completion`

**Done when**:

- [ ] Deploy log shows `release_command` exit 0 and the machine started
- [ ] `fly machine list` shows exactly 1 app machine; `fly status` shows the `/health` check passing
- [ ] Gate check passes: `docker compose run --rm -T app mix precommit`
- [ ] Test count: baseline passes unchanged

**Tests**: manual
**Gate**: build

**Commit**: `docs(delivery): record deploy evidence`

---

### T9: Production smoke test (outward-facing)

**What**: Against `https://whiq.fly.dev`:
- create a bin
- `curl` a JSON body to its capture URL and see it on the open bin page (DEL-05)
- `curl http://...` gets a redirect to https (DEL-04)
- recorded `remote_ip` equals the caller's public IP (DEL-06)
- a forged `fly-client-ip` header does not change the recorded IP (DEL-07)

Record the evidence in `smoke.md`. If DEL-07 fails, add a fix task for plan B (right-parsed `x-forwarded-for`).
**Where**: `.specs/features/delivery/smoke.md` (modify)
**Depends on**: T8
**Reuses**: spec "Independent Test"
**Requirement**: DEL-04, DEL-05, DEL-06, DEL-07

**Tools**:

- MCP: `chrome-devtools` (bin page)
- Skill: `superpowers:verification-before-completion`

**Done when**:

- [ ] Each of DEL-04..07 has a command, its output and a pass/fail line in `smoke.md`
- [ ] Gate check passes: `docker compose run --rm -T app mix precommit`
- [ ] Test count: baseline passes unchanged

**Tests**: manual
**Gate**: build

**Commit**: `docs(delivery): record production smoke test`

---

### T10: Verify CI on GitHub (outward-facing)

**What**: With the user's go-ahead to push and open the PR, confirm on GitHub:
- the `checks` and `release-image` jobs run green on the PR (DEL-01, DEL-11)
- a throwaway branch with a formatting error fails `checks` (DEL-02); delete that branch afterwards

Record the run URLs in `smoke.md`.
**Where**: `.specs/features/delivery/smoke.md` (modify)
**Depends on**: T9
**Reuses**: `gh run list` / `gh run view`
**Requirement**: DEL-01, DEL-02, DEL-11

**Tools**:

- MCP: NONE
- Skill: `ecc:github-ops`

**Done when**:

- [ ] Green run URL for the PR and red run URL for the throwaway branch recorded
- [ ] Gate check passes: `docker compose run --rm -T app mix precommit`
- [ ] Test count: baseline passes unchanged

**Tests**: manual
**Gate**: build

**Commit**: `docs(delivery): record ci evidence`

---

## Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1 | generator output (one command) | ✅ Granular |
| T2 | 1 endpoint + route | ✅ Granular |
| T3 | 1 config key + its test | ✅ Granular |
| T4 | 1 file | ✅ Granular |
| T5 | 1 job | ✅ Granular |
| T6 | 1 job | ✅ Granular |
| T7 | 1 file | ✅ Granular |
| T8 | 1 deploy | ✅ Granular |
| T9 | 1 smoke run | ✅ Granular |
| T10 | 1 CI check | ✅ Granular |

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | phase 1 start | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T2 | T2 → T3 | ✅ Match |
| T4 | T3 | T3 → T4 | ✅ Match |
| T5 | None (after Phase 1) | phase 2 start | ✅ Match |
| T6 | T5 | T5 → T6 | ✅ Match |
| T7 | None (after Phase 2) | phase 3 start | ✅ Match |
| T8 | None (after Phase 3) | phase 4 start | ✅ Match |
| T9 | T8 | T8 → T9 | ✅ Match |
| T10 | T9 | T9 → T10 | ✅ Match |

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Release image | none (build gate) | none | ✅ OK |
| T2 | Controller / router | integration | integration | ✅ OK |
| T3 | Prod endpoint config | unit | unit | ✅ OK |
| T4 | `fly.toml` | none | none | ✅ OK |
| T5 | workflow | none | none | ✅ OK |
| T6 | workflow | none | none | ✅ OK |
| T7 | README | none | none | ✅ OK |
| T8 | Live deploy | manual smoke | manual | ✅ OK |
| T9 | Live deploy | manual smoke | manual | ✅ OK |
| T10 | Live CI | manual smoke | manual | ✅ OK |
