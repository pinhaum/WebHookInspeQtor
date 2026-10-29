# Retention Validation

**Result**: FAIL (iteration 0: 7/7 ACs have `file:line` evidence on the spec outcome, 0 spec-precision gaps, build gate green with 148 tests; sensor 13 mutants, 11 killed, 2 survived (M12, M13). Both survivors sit in the Oban supervision wiring, which the binding "Oban install" assumption requires.)

**Date**: 2026-10-29
**Spec**: `.specs/features/retention/spec.md`
**Diff range**: `dd695e1..7ac3fdb` (`914b670` spec, `8cb7926` Oban dep + pruner, `7ac3fdb` prune worker)
**Verifier**: independent sub-agent (author != verifier), fresh context

---

## Task Completion

Inline plan, no `tasks.md` (spec traceability row: "inline plan, no tasks.md"). All seven requirements have code in the diff:

| Area | Files | Status |
| ---- | ----- | ------ |
| Oban install | `mix.exs:77`, `config/config.exs:21-27`, `config/test.exs:35-36`, `lib/whiq/application.ex:13`, `priv/repo/migrations/20261029194701_add_oban_jobs_table.exs` | Done. Supervision wiring has no test (see Gap 1) |
| Delete function | `lib/whiq/inspector.ex:31-39` `delete_expired_bins/1` | Done |
| Worker | `lib/whiq/inspector/prune_expired_bins.ex:12-17` | Done |
| Index | `priv/repo/migrations/20261029194816_add_expires_at_index_to_bins.exs:5` | Done. Checked by inspection: `bins_expires_at_index` is present in `whiq_test` (`pg_indexes`) |

---

## Spec-Anchored Acceptance Criteria

Payload/conjunction rule: deletion tests compare the full set of remaining ids (`Repo.all(... select: b.id) == [id]`), not only a count. The returned count is also asserted exactly. The log assertion checks the level and the interpolated number.

| AC | Spec-defined outcome | `file:line` + assertion | Result |
| -- | -------------------- | ----------------------- | ------ |
| RET-01 | Every bin with `expires_at <= now` deleted (boundary inclusive; `now` = `DateTime.utc_now(:second)`) | `test/whiq/inspector_test.exs:446-447` bins at `now - 1s` and exactly `now`; `:450` `Inspector.delete_expired_bins(now) == 2`; `:452` `Repo.all(from(b in Bin, select: b.id)) == [later.id]`. Through the worker: `test/whiq/inspector/prune_expired_bins_test.exs:27` `Repo.all(...) == [live.id]` after `perform_job` | PASS |
| RET-02 | A deleted bin's captured requests are deleted too | `test/whiq/inspector_test.exs:459-461` two requests on the expired bin, one on the live bin; `:464` `delete_expired_bins(now) == 1`; `:466` `Repo.all(from(r in CapturedRequest, select: r.id)) == [kept.id]` (cascade from `create_requests.exs:6` `on_delete: :delete_all`) | PASS |
| RET-03 | Every bin with `expires_at > now` kept | `test/whiq/inspector_test.exs:448` bin at `now + 1s`; `:452` `== [later.id]`; worker `prune_expired_bins_test.exs:27` `== [live.id]` | PASS |
| RET-04 | Prune job scheduled once per hour | `test/whiq/oban_config_test.exs:19` `{Oban.Cron, opts} = List.keyfind(production_plugins(), Oban.Cron, 0)`; `:20` `{"@hourly", Whiq.Inspector.PruneExpiredBins} in Keyword.fetch!(opts, :crontab)` | PASS at config level (the spec Success Criteria set config as the evidence level). Starting that config under supervision is not asserted, see Gap 1 |
| RET-05 | No expired bins -> completes successfully, deletes nothing | Context `test/whiq/inspector_test.exs:472` `delete_expired_bins() == 0`, `:474` `== [live.id]`; worker `prune_expired_bins_test.exs:34` `perform_job(PruneExpiredBins, %{}) == :ok`, `:36` `== [live.id]`, `:37` `log =~ "[info] Pruned 0 expired bins"` | PASS |
| RET-06 | Number of deleted bins logged at info level | `test/whiq/inspector/prune_expired_bins_test.exs:28` `log =~ "[info] Pruned 1 expired bins"` (one expired bin, level raised to `:info` for this sync module, `:12-17`) | PASS |
| RET-07 | Finished Oban job rows older than 7 days pruned | `test/whiq/oban_config_test.exs:14` `{Oban.Pruner, opts} = List.keyfind(production_plugins(), Oban.Pruner, 0)`; `:15` `Keyword.fetch!(opts, :max_age) == {7, :days}` | PASS at config level, same caveat as RET-04 (Gap 1) |

**Status**: ✅ 7/7 ACs covered on the spec outcome. 0 spec-precision gaps.

**Assumptions table (binding)**:

- Clock: the worker calls `delete_expired_bins/0`, which defaults to `DateTime.utc_now(:second)` (`lib/whiq/inspector.ex:36`). The read path uses the same expression with `expires_at > ^now` (`lib/whiq/inspector.ex:169-172`). The two boundaries are complementary, and the inclusive boundary is asserted at `inspector_test.exs:447/450`. M1 and M11 kill a shifted boundary or clock.
- Deletion: one `Repo.delete_all`, cascade done by the database. ✅
- Oban install: dep, migration (`Oban.Migrations.up(version: 14)`; 14 is `@current_version` in `deps/oban/lib/oban/migrations/postgres.ex:9`) and `testing: :manual` are present. ✅ Supervision is present at `application.ex:13` but no test covers it (Gap 1).
- Job history: `pruner: [max_age: {7, :days}]` (non-deprecated key in Oban 2.24.2). ✅
- Index on `bins.expires_at`: present. ✅
- Batching (none) and failure handling (Oban default retries; the worker uses `use Oban.Worker` with the default `max_attempts`). ✅ Checked by inspection.

---

## Discrimination Sensor

Scratch: detached worktree `~/Projects/whiq-verifier-wt` at `7ac3fdb`, with `_build`, `deps` and `.env` copied. Each mutant was applied alone by exact unique string replacement through a Python helper, which kept a backup copy in the session scratchpad. The full suite ran with `docker compose -p whiq run --rm -T app mix test` from the worktree. Each mutant was restored from its backup, and the worktree's `git status --porcelain` was empty after every restore. Depth: expanded (13 mutants), because the feature deletes data.

| # | File:line | Mutation | Killed by | Result |
| - | --------- | -------- | --------- | ------ |
| M1 | `lib/whiq/inspector.ex:37` | `expires_at <= ^now` -> `<` (boundary) | `inspector_test.exs:450`, `:464` | ✅ Killed |
| M2 | `lib/whiq/inspector.ex:37` | filter dropped (`Repo.delete_all(Bin)`) | `inspector_test.exs:450`, `:464`; `prune_expired_bins_test.exs:27`, `:36` | ✅ Killed |
| M3 | `lib/whiq/inspector.ex:38` | return `0` instead of the count | `inspector_test.exs:450`, `:464`; `prune_expired_bins_test.exs:28` | ✅ Killed |
| M4 | `lib/whiq/inspector/prune_expired_bins.ex:15` | log line removed | `prune_expired_bins_test.exs:28`, `:37` | ✅ Killed |
| M5 | `lib/whiq/inspector/prune_expired_bins.ex:15` | `Logger.info` -> `Logger.debug` | `prune_expired_bins_test.exs:28`, `:37` | ✅ Killed |
| M6 | `lib/whiq/inspector/prune_expired_bins.ex:16` | worker returns `{:error, :boom}` | `prune_expired_bins_test.exs:25`, `:34` | ✅ Killed |
| M7 | `config/config.exs:27` | cron `@hourly` -> `@daily` | `oban_config_test.exs:20` | ✅ Killed |
| M8 | `config/config.exs:27` | cron worker -> `Whiq.Inspector` (not a worker) | `oban_config_test.exs:9` (`Oban.Config.new` raises; both tests fail) | ✅ Killed |
| M9 | `config/config.exs:26` | pruner `max_age: {7, :days}` -> `{1, :day}` | `oban_config_test.exs:15` | ✅ Killed |
| M10 | `config/config.exs:26` | `pruner:` key removed | `oban_config_test.exs:14` | ✅ Killed |
| M11 | `lib/whiq/inspector/prune_expired_bins.ex:14` | worker prunes with `now - 3600 s` (clock skew) | `prune_expired_bins_test.exs:27` | ✅ Killed |
| M12 | `lib/whiq/application.ex:13` | Oban child removed from the supervision tree | none (148 tests, 0 failures) | ❌ Survived -> Fix 1 |
| M13 | `lib/whiq/application.ex:13` | Oban started with `:cron` dropped from the env config | none (148 tests, 0 failures) | ❌ Survived -> Fix 2 |

**Isolation proof**: real tree `git status --porcelain` was empty before the sensor (baseline file is 0 bytes) and empty after. `HEAD` was `7ac3fdb` throughout. The worktree was unregistered and deleted with git worktree (remove `--force`, then prune). Afterwards `git worktree list` shows only the main tree, and the scratch directory no longer exists.

**Result**: 11/13 killed - FAIL ❌

Why the survivors survive: `oban_config_test.exs` rebuilds an `Oban.Config` from `Application.fetch_env!(:whiq, Oban)`. Nothing checks that the application starts Oban, or starts it with that env. The suite never exercises the path from config to running instance. In production, M12 means the cron never fires and job rows are never pruned (RET-04, RET-07 and the Goal "no bin survives more than about one hour past `expires_at`"), while every test stays green.

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ 10-line context function, 18-line worker, 6 config lines |
| Surgical changes | ✅ Only the files the spec needs, plus `mix.exs`/`mix.lock` for the dep |
| No scope creep | ✅ |
| Matches patterns | ✅ Clock expression matches `fetch_live_bin/2`; tests reuse `capture!`/`snapshot()` helpers; `use Oban.Testing` per Oban docs |
| Spec-anchored outcome check | ✅ Exact id sets, exact counts, level-prefixed log text |
| Per-layer coverage | ⚠️ Context and worker 1:1 with ACs; scheduling and pruning covered at config level only; supervision wiring not covered (Gap 1) |
| Every test maps to a spec requirement | ✅ All 7 new tests are labelled with RET ids |
| Documented guidelines followed: `AGENTS.md` | ✅ No `Process.sleep`. The module that changes the global Logger level is `async: false` and restores the level in `on_exit`. One module per file. Migrations were generated with timestamps |

Observation (non-blocking): `prune_expired_bins_test.exs` changes the global `Logger` level. It is `async: false` and restores the level, but async modules can run alongside it and may emit extra info logs during that window. This affects test output only, not correctness.

---

## Edge Cases

- [x] RET-05 no expired bins: context `inspector_test.exs:469-475`, worker `prune_expired_bins_test.exs:31-38`
- [x] Boundary `expires_at == now` is deleted: `inspector_test.exs:447`, `:450-452`

---

## Gate Check

- **Gate command**: `docker compose -p whiq run --rm -T app mix precommit` (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`)
- **Result**: exit 0; 148 tests, 0 failures, 0 skipped (seed 764509, 1.6 s)
- **`git status --porcelain` after gate**: empty (`format` changed nothing)
- **Test count before feature** (`dd695e1`, `git grep` of `test "`): 141
- **Test count after feature**: 148
- **Delta**: +7 (3 context, 2 worker, 2 config); none removed
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans

### Fix 1: Oban supervision is untested (M12) - Major

- **Root cause**: no test checks that `Whiq.Application` starts an Oban instance. Removing the child leaves 148/148 green, while in production the cron never fires and job rows are never pruned.
- **Fix task**: add a test (e.g. in `test/whiq/oban_config_test.exs`) that the running app has a started Oban instance on the app repo, e.g. `assert %Oban.Config{repo: Whiq.Repo} = Oban.config()` (`Oban.config/1` exists at `deps/oban/lib/oban.ex:665`). Under `testing: :manual` the running config has its plugins stripped (`deps/oban/lib/oban/config.ex:107-111`), so assert presence and repo, not plugins.
- **Verify**: M12 (remove `{Oban, ...}` from `application.ex` children) makes that test fail.
- **Priority**: Major (RET-04, RET-07, Goal)

### Fix 2: started Oban options are not tied to the asserted config (M13) - Minor

- **Root cause**: `oban_config_test.exs:9` builds the config from the env, not from what `Whiq.Application` passes to `{Oban, ...}`. Under `testing: :manual` the running instance strips plugins, so even Fix 1 cannot see `:cron`/`:pruner`.
- **Fix task** (options, pick one): (a) have the test read the Oban child spec that `Whiq.Application` builds (needs a small seam, e.g. a public function returning the child opts that both `start/2` and the test use); or (b) accept M13 as not discriminable under `testing: :manual`, given the one-line `Application.fetch_env!(:whiq, Oban)` child, and record that decision in STATE.md.
- **Verify**: with (a), M13 (`Keyword.delete(..., :cron)` in the child) fails the config test.
- **Priority**: Minor. This needs an orchestrator/user decision: (b) is a legitimate acceptance.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| RET-01 | Implementing | ✅ Verified |
| RET-02 | Implementing | ✅ Verified |
| RET-03 | Implementing | ✅ Verified |
| RET-04 | Implementing | ❌ Needs Fix (supervision wiring, Fix 1) |
| RET-05 | Implementing | ✅ Verified |
| RET-06 | Implementing | ✅ Verified |
| RET-07 | Implementing | ❌ Needs Fix (supervision wiring, Fix 1) |

---

## Summary

**Overall**: ❌ Not Ready (one Major fix task)

**Spec-anchored check**: 7/7 ACs matched the spec outcome, 0 spec-precision gaps
**Sensor**: 11/13 killed (M12, M13 survived)
**Gate**: 148 passed, 0 failed

**What works**: inclusive deletion boundary, cascade of requests, live bins kept, empty run, info-level count log, worker return value, hourly cron and 7-day pruner values, all discriminated by the tests.

**Issues found**: the Oban supervision child can be removed or altered without any test failing (Fix 1, Fix 2).

**Next steps**: route Fix 1 (and Fix 2 or its acceptance) to an implementer, then re-dispatch the Verifier (iteration 1 of max 3).
