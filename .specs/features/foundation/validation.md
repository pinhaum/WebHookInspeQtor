# Foundation Validation

**Date**: 2026-10-27
**Spec**: `.specs/features/foundation/spec.md`
**Diff range**: `af5dd76..31ee2ac` (4 commits)
**Verifier**: independent sub-agent (author != verifier)
**Verdict**: PASS

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | Done | Dockerfile.dev, compose.yaml, .env.example present; image builds and runs (gate ran through it) |
| T2 | Done | Phoenix app generated; `mix precommit` green; config/dev.exs binds 0.0.0.0 and reads `DATABASE_HOST` |
| T3 | Done | Endpoint stripped of Parsers/MethodOverride/Plug.Head; HEAD test added |
| T4 | Done | `/h` scope + stub controller + 6 tests |

tasks.md header still says `Status: In Progress` (housekeeping, not a defect).

---

## Spec-Anchored Acceptance Criteria

| Criterion | Spec-defined outcome | `file:line` + assertion | Result |
| --------- | -------------------- | ----------------------- | ------ |
| FND-01 body request to `/h/:token` | dispatched to CaptureController, `body_params` unfetched, body fully readable via `read_body/2` | `test/whiq_web/controllers/capture_controller_test.exs:5` `assert conn.private.phoenix_controller == WhiqWeb.CaptureController`; `:18` `assert %Plug.Conn.Unfetched{aspect: :body_params} = conn.body_params`; `:19` `assert {:ok, ^body, _conn} = Plug.Conn.read_body(conn)` | PASS |
| FND-02 HEAD `/h/:token` | method `"HEAD"` at controller | `capture_controller_test.exs:25` `assert conn.method == "HEAD"` (+ `:5` controller) | PASS |
| FND-03 POST `_method=DELETE` urlencoded | method `"POST"` | `capture_controller_test.exs:35` `assert conn.method == "POST"` (+ `:5`) | PASS |
| FND-04 `/h/:token/any/sub/path` | dispatched to capture controller | `capture_controller_test.exs:39` `get("/h/tok123/any/sub/path") |> assert_captured()` (`:5`); `:41` `assert conn.status == 200` | PASS |
| FND-05 `PROPFIND` `/h/:token` | dispatched to capture controller | `capture_controller_test.exs:45` `dispatch(@endpoint, "PROPFIND", ...) |> assert_captured()`; `:47` `assert conn.method == "PROPFIND"` | PASS |
| FND-06 HEAD `/` | 200, empty body | `test/whiq_web/controllers/page_controller_test.exs:11` `assert conn.status == 200`; `:12` `assert conn.resp_body == ""` | PASS |
| FND-07 `Accept: application/xml` on `/h/:token` | 200 | `capture_controller_test.exs:57` `assert conn.status == 200` | PASS |
| FND-08 `docker compose up` serves :4000 with reload | home page 200, code reloading | Smoke: `curl -s -o /dev/null -w '%{http_code}' http://localhost:4000/` returned `200` (re-run by verifier); `compose.yaml:4-18` (command `mix setup && mix phx.server`, port 4000, bind mount); `config/dev.exs` `code_reloader: true`, `http: [ip: {0,0,0,0}]`. Reload itself relied on the author's template-edit smoke (not re-run) | PASS (smoke, no ExUnit by design) |
| FND-09 `docker compose run --rm app mix test` against compose Postgres | suite runs against compose Postgres | Verifier ran gate: 12 tests, 0 failures; `config/test.exs` `hostname: System.get_env("DATABASE_HOST", ...)`, `compose.yaml` `DATABASE_HOST: db` | PASS |
| FND-10 `mix precommit` | compile warnings-as-errors, format, test pass | `mix.exs:98` alias `["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]`; run exit 0 | PASS |
| FND-11 files owned by host user | no file outside `.git` owned by another user | `compose.yaml:7` `user: "${UID:-1000}:${GID:-1000}"`, `:10` `HOME: /tmp`; `find . -path ./.git -prune -o ! -user $(id -u) -print` printed nothing (re-run by verifier) | PASS (smoke) |

**Status**: All 11 ACs covered, assertions target the spec-defined outcomes. No spec-precision gaps (FND-04/FND-05 specify dispatch only; tests assert dispatch via `phoenix_controller`, status/method additionally).

---

## Discrimination Sensor

Scratch: temporary git worktree under the session scratchpad. The scratchpad `/tmp` is not visible to the Docker daemon as a bind mount, so the worktree was copied into a throwaway container (`docker create` + `docker cp`) on the compose network (`whiq_default`, db host `db`) and run with `mix test`. Baseline in scratch: 12 tests, 0 failures. Real tree was never touched.

| # | File | Mutation | Killed? |
| - | ---- | -------- | ------- |
| a | `lib/whiq_web/endpoint.ex:48` | `plug :head_outside_capture` -> unconditional `plug Plug.Head` | Killed (FND-02 test `:22`) |
| b | `endpoint.ex` | re-add `Plug.Parsers` (urlencoded + json) before router | Killed (FND-01 test `:9`) |
| c | `endpoint.ex` | re-add `Plug.Parsers` urlencoded + `Plug.MethodOverride` | Killed (FND-03 test `:28`) |
| d | `router.ex:23` | delete `/:token/*path` route | Killed (FND-04 test `:38`) |
| e | `endpoint.ex:53` | head-skip clause never matches (`"h"` -> `"zz"`) | Killed (FND-02 test `:22`) |
| f | `router.ex:22` | only first route changed `match :*` -> `get` | Survived - equivalent mutant: `/:token/*path` also matches `/h/:token` with an empty glob, so the second route still covers every method on that path. Not a test weakness |
| g | `router.ex:22-23` | both routes `match :*` -> `get` | Killed (4 failures: HEAD, POST, PROPFIND, body test) |
| h | `router.ex:21` | add `pipe_through :browser` to `/h` scope | Killed (FND-07 test `:50`, `accepts ["html"]`) |

**Sensor depth**: lightweight (8 injected; non-P0 feature)
**Result**: 7 killed, 1 survived (equivalent, no fix task) - PASS

Cleanup: worktree removed with `--force`, `git worktree prune` run, `git worktree list` shows only the main tree, `diff -r` of scratch vs real `lib/` identical before removal, real `git status --porcelain` equals baseline (` M README.md` only, user's change untouched).

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | PASS (controller is 3 lines; one private function plug) |
| Surgical changes | PASS (non-generated edits limited to endpoint, router, config, compose files) |
| No scope creep | PASS |
| Matches patterns | PASS (Phoenix conventions; `async: true` ConnCase) |
| Spec-anchored outcome check | PASS |
| Per-layer Coverage Expectation (one test per FND capture AC) | PASS (6 capture tests + 1 page test) |
| Every test maps to a spec requirement | PASS (generated tests: `GET /`, error_html, error_json are scaffold, not unclaimed feature tests) |
| Documented guidelines followed | none - strong defaults applied (tasks.md matrix) |

---

## Edge Cases

- [x] Files created by the app container owned by host user (FND-11): `find` printed nothing.
- [x] Known deviation: `Plug.MethodOverride` dropped entirely instead of moved into `:browser` (AD-001). Evaluated as correct: a pipeline plug runs after route matching so it cannot affect routing, and nothing in scope needs `_method` on HTML forms (LiveView uses the socket). Mutation c shows its endpoint re-addition would break FND-03, and the router has no `Plug.MethodOverride`.
- [x] Known deviation: `/h` scope without pipeline instead of an empty `:capture` pipeline. Evaluated as equivalent and simpler; mutation h shows it is the difference that keeps FND-07 green.

---

## Gate Check

- **Gate command**: `docker compose run --rm app mix precommit`
- **Result**: 12 passed, 0 failed, 0 skipped (exit 0)
- **Test count before feature**: 5 (generated suite)
- **Test count after feature**: 12
- **Delta**: +7 (1 HEAD `/` + 6 capture)
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans

None required.

Advisory (non-blocking documentation drift):
1. AD-001 in `.specs/STATE.md` still says MethodOverride moves to `:browser` and that a `:capture` pipeline exists; actual code drops MethodOverride and uses a pipeline-less `/h` scope. Update AD-001 text (Minor).
2. `tasks.md` header `Status: In Progress` and spec Goals/Success Criteria checkboxes are unticked (Cosmetic).
3. FND-08 live code reload was not re-verified by the verifier (relies on author smoke evidence); only HTTP 200 re-checked (Minor).

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| FND-01..FND-07 | Done | Verified |
| FND-08 | Done | Verified (smoke) |
| FND-09..FND-10 | Done | Verified |
| FND-11 | Done | Verified (smoke) |

(spec.md not modified by the verifier; status update left to the orchestrator.)

---

## Summary

**Overall**: Ready

**Spec-anchored check**: 11/11 ACs matched spec outcome (9 by ExUnit/gate, FND-08 and FND-11 by smoke), 0 spec-precision gaps
**Sensor**: 7/8 mutations killed (1 equivalent survivor)
**Gate**: 12 passed, 0 failed

**What works**: capture path unaltered for body, HEAD, method override, sub-paths and custom methods; HEAD `/` still 200 empty; containerized dev environment runs tests and serves :4000 as host user.

**Issues found**: only the advisory documentation drift above.

**Next steps**: update AD-001 wording; mark tasks/spec status done.
