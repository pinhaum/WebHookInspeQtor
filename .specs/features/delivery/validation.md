# Delivery Validation

**Result**: PASS

**Date**: 2026-10-30
**Spec**: `.specs/features/delivery/spec.md`
**Diff range**: `141039b..015ba5a` (implementation `79002c2..aec1887`, fix commit `015ba5a`)
**Verifier**: independent sub-agent (author != verifier), re-verification iteration 2 of 3
**Scope**: DEL-01, DEL-02, DEL-03, DEL-04, DEL-08, DEL-09, DEL-11, DEL-13. DEL-05/06/07/12 are Retired (live deploy descoped) and not assessed.

---

## Iteration History

| Iteration | HEAD | Verdict | Open gaps |
| --------- | ---- | ------- | --------- |
| 1 | `aec1887` | Not ready | Fix 1 (Mutant B), Fix 2 (DEL-08 live link), Fix 3 (Mutant F, DEL-03 manual only), Fix 4 (Mutant D2) |
| 2 | `015ba5a` | Ready | None blocking; Fix 3 closed as accepted manual evidence |

`015ba5a` touches only `test/whiq_web/controllers/health_controller_test.exs` (+12), `test/whiq_web/prod_force_ssl_test.exs` (+7), `.specs/features/delivery/spec.md` (DEL-08 text, Success Criteria) and `.specs/features/delivery/smoke.md` (migrate evidence). No production code changed, so the iteration-1 live CI and manual migrate evidence still apply to the code under test.

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | Done | Image builds; `bin/migrate` verified by hand on a fresh database (DEL-03), recorded in `smoke.md:25-27` |
| T2 | Done | Pipeline-free placement of `/health` now guarded (Mutant B killed) |
| T3 | Done | `hosts` exclusion now guarded (Mutant D2 killed) |
| T4 | Done | All keys present with the stated values (`fly.toml:3-30`) |
| T5 | Done | actionlint clean; live run green |
| T6 | Done | actionlint clean; `push: false`, no login step |
| T7 | Done | README matches amended DEL-08 |
| T10 | Done | Run URLs recorded in `smoke.md:5-23` and confirmed with `gh run view` (iteration 1) |

---

## Spec-Anchored Acceptance Criteria

| Criterion | Spec-defined outcome | Evidence (`file:line` + assertion) | Result |
| --------- | -------------------- | ---------------------------------- | ------ |
| DEL-01: on push to `main` / PR, CI runs format, compile, unused-deps and test | The 4 checks run | `.github/workflows/ci.yml:3-6` (`push: branches: [main]`, `pull_request`), `.github/workflows/ci.yml:50-53` (the 4 checks). Live: run 41092498517 (`pull_request`), job `checks`, all 4 steps `success` (`smoke.md:9-12`) | PASS (push-to-main trigger declared, not yet fired; `smoke.md:31`) |
| DEL-02: any failing check marks the run failed | Run conclusion `failure` | Run 41092967640: `checks` failed at `mix format --check-formatted` (`smoke.md:16-23`). Steps have no `continue-on-error` (`.github/workflows/ci.yml:49-53`) | PASS |
| DEL-11: CI builds the release image without pushing | Image built, nothing pushed | `.github/workflows/ci.yml:57-69` (`docker/build-push-action@v7` line 64, `push: false` line 67, no login step). Live `release-image` `success` in both runs | PASS |
| DEL-03: release `/app/bin/migrate` on an empty DB applies every pending migration, exits 0 | Exit 0 and all 5 migrations applied | Manual: iteration-1 Verifier built the image from `aec1887`, ran `/app/bin/migrate` on a fresh DB: exit 0, 5/5 versions in `schema_migrations`, `oban_jobs` present, second run exit 0. Recorded in `smoke.md:25-27`, which also instructs checking the applied count, not only the exit code. Code: `lib/whiq/release.ex:12`, `rel/overlays/bin/migrate:5`; neither changed in `aec1887..015ba5a` | PASS (manual evidence; see Accepted Risk) |
| DEL-04: plain-HTTP request with a non-local host is redirected to HTTPS under prod config | Redirect to `https://` | `test/whiq_web/prod_force_ssl_test.exs:46-48` - `assert conn.status == 301`, `String.starts_with?(location, "https://#{@host}")`; `test/whiq_web/prod_force_ssl_test.exs:57-59` - `assert conn.status == 307` for `POST /h/abc`. Options read from the real `config/prod.exs` (`test/whiq_web/prod_force_ssl_test.exs:10-15`). Local-host counterpart (T3 "keeping `hosts`"): `test/whiq_web/prod_force_ssl_test.exs:35-39` - `refute conn.halted`, `assert conn.status == nil` for `http://localhost/` | PASS |
| DEL-08 (amended, `spec.md:91`): README states deploy-ready but not deployed; local setup with `docker compose`; architecture overview; "Decisions" from `.specs/STATE.md` | All four present | Deploy-ready/not deployed `README.md:7`; setup `README.md:17-30` (`docker compose up`, `docker compose run --rm app mix test`); architecture `README.md:32-38`; Decisions AD-001..AD-008 `README.md:40-51`, matching `.specs/STATE.md`, link at `README.md:42` | PASS |
| DEL-09: README documents lowercased header names and plain-HTTP captures redirected | Both limits stated | `README.md:60`, `README.md:61` | PASS |
| DEL-13: Fly health check over internal HTTP gets 200, not a redirect | 200 on plain HTTP | App: `test/whiq_web/controllers/health_controller_test.exs:7-10` - `assert conn.status == 200`, `text/plain`, body `"ok"`; pipeline-free: `test/whiq_web/controllers/health_controller_test.exs:22-23` - `accept: application/json` still `200`, `x-frame-options` absent; no DB: `test/whiq_web/controllers/health_controller_test.exs:41-42`. Config: `test/whiq_web/prod_force_ssl_test.exs:31-32` - `refute conn.halted`, `assert conn.status == nil` for plain-HTTP `GET /health`. Fly side: `fly.toml:22-27` | PASS |

**Status**: 8/8 ACs met with evidence; 0 spec-precision gaps open.

Judgement on the new tests: the `/health` pipeline test asserts two outcomes that the `:browser` pipeline (`lib/whiq_web/router.ex:4-12`) changes deterministically (`accepts ["html"]` -> 406 for JSON, `put_secure_browser_headers` -> `x-frame-options`), so it guards the design constraint "no pipeline" behind DEL-13 rather than restating implementation. The localhost case asserts the outcome of the `hosts` exclusion (pass-through, not halted), the mirror image of DEL-04's "non-local host" clause. Both are spec-anchored. The localhost test carries no requirement tag; it traces to T3, not an AC (minor, non-blocking).

---

## Discrimination Sensor

Scratch: detached worktree at `015ba5a` in `../whiq-verifier-wt`, `_build`/`deps` copied with `cp -a`, tests run with `docker compose run --rm -T -v <wt>:/app app mix test ...` (mount confirmed with a marker file). One fault at a time; file restored from a backup and `git diff --quiet` checked before the next. Baseline in the worktree: 157 tests, 0 failures.

| # | Iter | File:line | Mutation | Tests run | Killed? |
| - | ---- | --------- | -------- | --------- | ------- |
| A1 | 1 | `lib/whiq_web/controllers/health_controller.ex:7` | body `"ok"` -> `"OK"` | health_controller_test | Killed |
| A2 | 1 | `lib/whiq_web/controllers/health_controller.ex:7` | status 200 -> 204 | health_controller_test | Killed |
| A3 | 1 | `lib/whiq_web/controllers/health_controller.ex:7` | `text/2` -> `json/2` | health_controller_test | Killed |
| A4 | 1 | `lib/whiq_web/controllers/health_controller.ex:7` | add `Whiq.Repo.query!("SELECT 1")` | health_controller_test | Killed |
| B | 1 | `lib/whiq_web/router.ex:29-30` | add `pipe_through :browser` to the `/health` scope | health_controller_test + full suite | Survived |
| C | 1 | `config/prod.exs:17` | drop `paths: ["/health"]` | prod_force_ssl_test | Killed |
| D1 | 1 | `config/prod.exs:18` | add `whiq.fly.dev` to excluded hosts | prod_force_ssl_test | Killed |
| D2 | 1 | `config/prod.exs:18` | drop `hosts: ["localhost", "127.0.0.1"]` | prod_force_ssl_test | Survived |
| E1 | 1 | `config/prod.exs:15` | drop `rewrite_on: [:x_forwarded_proto]` | prod_force_ssl_test | Killed |
| E2 | 1 | `config/prod.exs:17` | `paths: ["/health"]` -> `["/"]` | prod_force_ssl_test | Killed |
| F | 1 | `lib/whiq/release.ex:12` | `:up, all: true` -> `:up, step: 1` | manual migrate run | Survived automated gates; caught by manual count |
| B | 2 | `lib/whiq_web/router.ex:30` | add `pipe_through :browser` to the `/health` scope | health_controller_test | **Killed** (1/3 fail: "skips the browser pipeline") |
| D2 | 2 | `config/prod.exs:18` | drop `hosts: [...]` | prod_force_ssl_test | **Killed** (1/5 fail: "on localhost passes through") |
| A1 | 2 | `lib/whiq_web/controllers/health_controller.ex:7` | body `"ok"` -> `"OK"` | health_controller_test | Killed (2/3 fail) - no regression |
| C | 2 | `config/prod.exs:17` | drop `paths: ["/health"]` | prod_force_ssl_test | Killed (1/5 fail) - no regression |
| E1 | 2 | `config/prod.exs:15` | drop `rewrite_on: [:x_forwarded_proto]` | prod_force_ssl_test | Killed (1/5 fail) - no regression |

**Sensor depth**: lightweight+ (11 mutants iteration 1, 5 re-run iteration 2)
**Sensor outcome**: iteration 2 - 5/5 killed. Cumulative - 10/11 killed by automated tests; F not rerun (no code change in `lib/whiq/release.ex` or `rel/`), covered by the accepted manual evidence below.

Post-sensor: worktree removed with `git worktree remove --force`, `git worktree prune`; main tree `git status --porcelain` = `?? .specs/features/delivery/validation.md` only (matches baseline).

---

## Accepted Risk: DEL-03 without an automated gate

DEL-03 is phrased as a release-image behavior and its own Independent Test (`spec.md:79`) is a manual procedure: "Build the release image and run its migrate script against a fresh compose database." Manual evidence therefore matches the spec's verification method. The evidence checks the spec outcome precisely (5/5 applied plus exit 0, not exit code alone), and `smoke.md:27` records that distinction for future re-runs. Residual risk: a regression in `lib/whiq/release.ex` (Mutant F class) would pass CI. Proportionate for a study project with no live deploy; the optional CI step from iteration-1 Fix 3 remains a nice-to-have.

---

## Static Checks (non-test-gated artefacts)

Unchanged since iteration 1 (`015ba5a` touches no workflow, Dockerfile or `fly.toml`).

| Artefact | Check | Result |
| -------- | ----- | ------ |
| `.github/workflows/ci.yml` | actionlint | rc 0, no findings (iteration 1) |
| `.github/workflows/ci.yml:10-11` | Versions vs `Dockerfile.dev:1` and `Dockerfile:20-21` | Consistent |
| `fly.toml:3-30` | Every key and value from T4 / design | All present |
| `Dockerfile` | Built by the Verifier from `aec1887` | Builds |

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | OK |
| Surgical changes | OK - fix commit is tests and specs only |
| No scope creep | OK |
| Matches patterns | OK - new tests reuse the existing ConnCase / `Plug.SSL.call` style |
| Spec-anchored outcome check | OK - 8/8 |
| Per-layer coverage expectation | OK - "no pipeline" now asserted on observable outcomes |
| Every test maps to a requirement | Mostly - localhost case traces to T3 only, untagged |
| Documented guidelines followed | `AGENTS.md` - ConnTest used, no raw-HTML assertions |

---

## Edge Cases

- [x] DEL-13 health check over plain HTTP: 200 at app and `force_ssl` layer
- [x] `/health` stays outside any pipeline: guarded by `test/whiq_web/controllers/health_controller_test.exs:16-24`
- [x] Local hosts excluded from `force_ssl`: guarded by `test/whiq_web/prod_force_ssl_test.exs:35-40`

---

## Gate Check

- **Gate command**: `docker compose run --rm -T -v <wt>:/app app mix test` (scratch worktree at `015ba5a`)
- **Outcome**: 157 tests, 0 failures
- **Test count before feature**: 149
- **Test count after feature**: 157 (iteration 1: 155; `015ba5a` adds 2)
- **Delta**: +8
- **Live CI**: run 41092498517 green on `7b498f1`; `015ba5a` not yet run in CI (adds tests only; passes locally)

---

## Remaining Gaps (non-blocking)

1. DEL-03 has no automated guard (Mutant F class); accepted as manual evidence per the spec's own Independent Test.
2. `spec.md:5` Problem Statement still mentions "a live URL" and "a deploy to Fly.io"; Goals, Out of Scope, DEL-08 and Success Criteria are consistent with the descope. Cosmetic drift.
3. The localhost force_ssl test has no requirement tag (traces to T3).

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| DEL-01 | Verified | Verified |
| DEL-02 | Verified | Verified |
| DEL-03 | Verified (manual) | Verified (manual evidence, accepted) |
| DEL-04 | Verified | Verified |
| DEL-08 | Needs Fix | Verified |
| DEL-09 | Verified | Verified |
| DEL-11 | Verified | Verified |
| DEL-13 | Needs Fix | Verified |

---

## Summary

**Overall**: Ready

**Spec-anchored check**: 8/8 ACs matched spec outcome
**Sensor**: iteration 2 - 5 injected, 5 killed (B and D2 now killed; A1, C, E1 no regression)
**Gate**: 157 passed, 0 failed

**Next steps**: none required. Optional: automate DEL-03 in CI, tidy `spec.md:5`.
