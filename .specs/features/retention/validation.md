# Retention Validation

**Result**: PASS (iteration 1: 7/7 ACs have `file:line` evidence on the spec outcome, 0 spec-precision gaps; build gate green with 149 tests; sensor iteration 1 ran 7 valid mutants, 6 killed and 1 accepted (M13, a recorded spec decision). One more mutant crashed at app boot and is excluded.)

**Date**: 2026-10-29
**Spec**: `.specs/features/retention/spec.md`
**Diff range**: `dd695e1..5a4be4a` (feature `dd695e1..7ac3fdb`; iteration-0 report `51397ec`; fix iteration `51397ec..5a4be4a`)
**Verifier**: independent sub-agent (author != verifier)

## History

- **Iteration 0** (`dd695e1..7ac3fdb`, report committed in `51397ec`): FAIL. 148 tests green, 7/7 ACs on the spec outcome, 0 spec-precision gaps. Sensor: 13 mutants, 11 killed, 2 survived:
  - M12: the Oban child was removed from `lib/whiq/application.ex:13`.
  - M13: Oban was started with `:cron` dropped from its options.
  Routed as Fix 1 (Major) and Fix 2 (Minor, accept or add a seam).
- **Iteration 1** (this report, `5a4be4a`): Fix 1 adds `test/whiq/oban_config_test.exs:23-25`. Fix 2 was resolved by acceptance: a new row in the spec Assumptions table, "Oban child options under test". The fix iteration changed no production code: `git diff 7ac3fdb..5a4be4a` touches only `test/`, `.specs/`.

---

## Task Completion

| Area | Files | Status |
| ---- | ----- | ------ |
| Oban install | `mix.exs:77`, `config/config.exs:21-27`, `config/test.exs:35-36`, `lib/whiq/application.ex:13`, `priv/repo/migrations/20261029194701_add_oban_jobs_table.exs` | Done. Supervision is now asserted (`oban_config_test.exs:24`) |
| Delete function | `lib/whiq/inspector.ex:31-39` `delete_expired_bins/1` | Done |
| Worker | `lib/whiq/inspector/prune_expired_bins.ex:12-17` | Done |
| Index | `priv/repo/migrations/20261029194816_add_expires_at_index_to_bins.exs:5` | Done. Checked by inspection: `bins_expires_at_index` is present in `whiq_test` |
| Fix 1 (iteration 0) | `test/whiq/oban_config_test.exs:23-25` | Done |
| Fix 2 (iteration 0) | `.specs/features/retention/spec.md`, Assumptions row "Oban child options under test" | Accepted as a recorded decision (see below) |

---

## Spec-Anchored Acceptance Criteria

Payload/conjunction rule: deletion tests compare the full set of remaining ids, not just a count. The returned count is also asserted exactly. The log assertion checks both the level and the interpolated number.

| AC | Spec-defined outcome | `file:line` + assertion | Result |
| -- | -------------------- | ----------------------- | ------ |
| RET-01 | Every bin with `expires_at <= now` deleted (boundary inclusive; `now` = `DateTime.utc_now(:second)`) | `test/whiq/inspector_test.exs:446-447` bins at `now - 1s` and exactly `now`; `:450` `Inspector.delete_expired_bins(now) == 2`; `:452` `Repo.all(from(b in Bin, select: b.id)) == [later.id]`. Worker: `test/whiq/inspector/prune_expired_bins_test.exs:27` `== [live.id]` after `perform_job` | PASS |
| RET-02 | A deleted bin's captured requests deleted too | `test/whiq/inspector_test.exs:459-461` 2 requests on the expired bin, 1 on the live bin; `:464` `delete_expired_bins(now) == 1`; `:466` `Repo.all(from(r in CapturedRequest, select: r.id)) == [kept.id]` | PASS |
| RET-03 | Every bin with `expires_at > now` kept | `test/whiq/inspector_test.exs:448` bin at `now + 1s`; `:452` `== [later.id]`; worker `prune_expired_bins_test.exs:27` | PASS |
| RET-04 | Prune job scheduled once per hour | `test/whiq/oban_config_test.exs:20` `{"@hourly", Whiq.Inspector.PruneExpiredBins} in Keyword.fetch!(opts, :crontab)` of the `Oban.Cron` plugin built from the app config; `:24` `%Oban.Config{repo: Whiq.Repo} = Oban.config()` (Oban runs under the app) | PASS |
| RET-05 | No expired bins: completes, deletes nothing | `test/whiq/inspector_test.exs:472` `delete_expired_bins() == 0`, `:474`; worker `prune_expired_bins_test.exs:34` `perform_job(...) == :ok`, `:36` `== [live.id]`, `:37` `log =~ "[info] Pruned 0 expired bins"` | PASS |
| RET-06 | Deleted count logged at info level | `test/whiq/inspector/prune_expired_bins_test.exs:28` `log =~ "[info] Pruned 1 expired bins"` | PASS |
| RET-07 | Finished Oban job rows older than 7 days pruned | `test/whiq/oban_config_test.exs:15` `Keyword.fetch!(opts, :max_age) == {7, :days}` of the `Oban.Pruner` plugin; `:24` Oban runs under the app | PASS |

**Status**: ✅ 7/7 ACs covered on the spec outcome. 0 spec-precision gaps.

**Binding assumptions**:

- Clock: the worker calls `delete_expired_bins/0`, which defaults to `DateTime.utc_now(:second)` (`lib/whiq/inspector.ex:36`). This is the same expression as the read path (`lib/whiq/inspector.ex:169-172`, `expires_at > ^now`). ✅
- Deletion is a single `delete_all` that relies on the database cascade (`create_requests.exs:6`). ✅
- Oban install: dep, migration at version 14 (= `@current_version`, `deps/oban/lib/oban/migrations/postgres.ex:9`), supervision (now asserted), `testing: :manual`. ✅
- Job history uses `pruner: [max_age: {7, :days}]`. ✅
- The `bins.expires_at` index is present. ✅
- No batching; default retries. ✅ (inspection)

**M13 acceptance (Fix 2)**: the new Assumptions row is acceptable as a recorded decision. It states:

- the exact wiring: `start/2` passes `Application.fetch_env!(:whiq, Oban)` unchanged, which matches `lib/whiq/application.ex:13`;
- what the tests do cover: the env normalized by `Oban.Config.new/1`, plus the running instance on `Whiq.Repo`;
- the named mutant (M13), and why it cannot be detected: `testing: :manual` strips plugins from the running config. I confirmed this in `deps/oban/lib/oban/config.ex:107-111`.

The residual risk is narrow. It needs an edit to the options inside the one-line child in `start/2`, and that edit is visible in review. The row is marked `Confirmed? n`, like the other agent-made rows. The user can flip it when reviewing the spec. This is non-blocking.

---

## Discrimination Sensor

Scratch: detached worktree `~/Projects/whiq-verifier-wt` at `5a4be4a`, with `_build`, `deps` and `.env` copied.

- Each mutant was applied alone, by exact unique string replacement through a Python helper. The helper saved a backup copy in the session scratchpad.
- Each run was the full suite: `docker compose -p whiq run --rm -T app mix test`, started from the worktree.
- Each mutant was then restored from its backup. The worktree's `git status --porcelain` was empty after every restore.
- Depth: expanded. Iteration 0 ran 13 mutants. Iteration 1 re-ran the survivors and a sample of killed mutants, and added new mutants on the fix area.

### Iteration 1

| # | File:line | Mutation | Killed by | Result |
| - | --------- | -------- | --------- | ------ |
| M12 | `lib/whiq/application.ex:13` | Oban child removed from the supervision tree | `oban_config_test.exs:24` | ✅ Killed (was a survivor) |
| M15 | `lib/whiq/application.ex:13` | Oban started under another name (`name: Whiq.OtherOban`) | `oban_config_test.exs:24` | ✅ Killed (fresh) |
| M1 | `lib/whiq/inspector.ex:37` | `expires_at <= ^now` -> `<` | `inspector_test.exs:450`, `:464` | ✅ Killed (re-run) |
| M5 | `lib/whiq/inspector/prune_expired_bins.ex:15` | `Logger.info` -> `Logger.debug` | `prune_expired_bins_test.exs:28`, `:37` | ✅ Killed (re-run) |
| M7 | `config/config.exs:27` | cron `@hourly` -> `@daily` | `oban_config_test.exs:20` | ✅ Killed (re-run) |
| M9 | `config/config.exs:26` | pruner `{7, :days}` -> `{1, :day}` | `oban_config_test.exs:15` | ✅ Killed (re-run) |
| M13 | `lib/whiq/application.ex:13` | Oban started with `:cron` dropped | none (149 tests, 0 failures) | ⚖️ Survived, accepted by the spec Assumptions row "Oban child options under test" |
| M14 | `lib/whiq/application.ex:13` | `:repo` replaced by a nonexistent module | app boot fails in `Oban.Config.new/1` before tests run | Not counted (it fails at boot, so no test is needed to catch it) |

**Isolation proof**: the real tree `git status --porcelain` was empty before and after, and `HEAD` stayed at `5a4be4a` throughout. The worktree was unregistered and deleted with git worktree (remove `--force`, then prune). Afterwards `git worktree list` shows only the main tree, and the scratch directory no longer exists.

**Result**: 6/6 non-accepted valid mutants killed, and 1 survivor accepted by a recorded spec decision - PASS ✅

### Iteration 0 (kept for history)

| # | File:line | Mutation | Result |
| - | --------- | -------- | ------ |
| M1 | `lib/whiq/inspector.ex:37` | `<=` -> `<` | ✅ Killed (`inspector_test.exs:450`, `:464`) |
| M2 | `lib/whiq/inspector.ex:37` | filter dropped | ✅ Killed |
| M3 | `lib/whiq/inspector.ex:38` | return `0` | ✅ Killed |
| M4 | `prune_expired_bins.ex:15` | log removed | ✅ Killed (`prune_expired_bins_test.exs:28`, `:37`) |
| M5 | `prune_expired_bins.ex:15` | log at debug | ✅ Killed |
| M6 | `prune_expired_bins.ex:16` | returns `{:error, :boom}` | ✅ Killed (`:25`, `:34`) |
| M7 | `config/config.exs:27` | `@daily` | ✅ Killed (`oban_config_test.exs:20`) |
| M8 | `config/config.exs:27` | cron worker `Whiq.Inspector` | ✅ Killed (`Oban.Config.new` raises) |
| M9 | `config/config.exs:26` | `max_age {1, :day}` | ✅ Killed (`oban_config_test.exs:15`) |
| M10 | `config/config.exs:26` | `pruner:` removed | ✅ Killed (`oban_config_test.exs:14`) |
| M11 | `prune_expired_bins.ex:14` | clock `now - 3600 s` | ✅ Killed (`prune_expired_bins_test.exs:27`) |
| M12 | `application.ex:13` | Oban child removed | ❌ Survived (now killed in iteration 1) |
| M13 | `application.ex:13` | `:cron` dropped from child options | ❌ Survived (now accepted in iteration 1) |

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ The fix is a 3-line test plus one spec row |
| Surgical changes | ✅ No production code touched in the fix iteration |
| No scope creep | ✅ The test-only seam was rejected |
| Matches patterns | ✅ The new test sits in the existing `oban_config_test.exs`, which is `async: true` and only reads |
| Spec-anchored outcome check | ✅ |
| Per-layer coverage | ✅ Context and worker are 1:1 with ACs. Schedule and pruner are covered at config level, and supervision by a running-instance check |
| Every test maps to a spec requirement | ✅ The new test is labelled RET-04 and RET-07 |
| Documented guidelines followed: `AGENTS.md` | ✅ |

Observation (non-blocking, carried from iteration 0): `prune_expired_bins_test.exs:12-17` raises the global Logger level in a sync module and restores it afterwards. Async modules may emit extra info logs during that window. This affects test output only.

---

## Edge Cases

- [x] RET-05 no expired bins: context `inspector_test.exs:469-475`, worker `prune_expired_bins_test.exs:31-38`
- [x] Boundary `expires_at == now` is deleted: `inspector_test.exs:447`, `:450-452`

---

## Gate Check

- **Gate command**: `docker compose -p whiq run --rm -T app mix precommit` (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`)
- **Result**: exit 0; 149 tests, 0 failures, 0 skipped
- **`git status --porcelain` after gate**: empty
- **Test count before feature** (`dd695e1`): 141
- **Test count at iteration 0**: 148
- **Test count after fix iteration**: 149
- **Delta**: +8 over the feature (+1 in the fix iteration); none removed
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans

None open. The iteration-0 Fix 1 is done (M12 killed). Fix 2 was resolved by acceptance (spec Assumptions row).

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| RET-01 | Implementing | ✅ Verified |
| RET-02 | Implementing | ✅ Verified |
| RET-03 | Implementing | ✅ Verified |
| RET-04 | Needs Fix (iteration 0) | ✅ Verified |
| RET-05 | Implementing | ✅ Verified |
| RET-06 | Implementing | ✅ Verified |
| RET-07 | Needs Fix (iteration 0) | ✅ Verified |

---

## Summary

**Overall**: ✅ Ready

**Spec-anchored check**: 7/7 ACs matched the spec outcome, 0 spec-precision gaps
**Sensor**: iteration 1 killed 6/6 valid non-accepted mutants; M13 was accepted by a spec decision
**Gate**: 149 passed, 0 failed

**What works**:

- the inclusive deletion boundary, the request cascade, keeping live bins, and the empty run;
- the info-level count log and the worker return value;
- the hourly cron, the 7-day pruner, and Oban running under the app.

**Issues found**: none blocking. M13 is a documented residual: the options are edited inside `start/2`, which tests cannot see under `testing: :manual`.

**Next steps**: optionally confirm the "Oban child options under test" Assumptions row (`Confirmed? n` -> `y`), and update the spec traceability statuses to Verified.
