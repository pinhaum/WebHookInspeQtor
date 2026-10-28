# Abuse Limits Validation

**Result**: PASS (iteration 1: 15/15 ACs with `file:line` evidence on the spec outcome, 0 spec-precision gaps; build gate green with 139 tests; sensor 14 mutants, 14 killed)

**Date**: 2026-10-28
**Spec**: `.specs/features/abuse-limits/spec.md`
**Diff range**: `5e2bc2f..174cf8b` (feature); fix iteration `2f83516..174cf8b` (T11 `6b806d4`, T12 `a146cee`, T13 `174cf8b`)
**Verifier**: independent sub-agent (author != verifier), fresh context

## History

- **Iteration 0** (`5e2bc2f..5af0ee8`, report committed in `2f83516`): FAIL. 134 tests green; sensor 25 mutants, 19 killed, 2 equivalent (M22, M25), 4 real survivors: M13 (bin limit keyed on the peer instead of `ClientIP.from_conn/1`), M16/M17 (multi-read accumulation in `CaptureSnapshot`), M18 (controller 404 when the bin is deleted before the lock). One spec-precision gap, SP-1 ("client IP" undefined for LIM-09/LIM-10). Fix 1-3 were routed as T11-T13.
- **Iteration 1** (this report): all four survivors killed, SP-1 closed by the spec line under LIM-10. No new gaps.

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1-T10 | Done | Unchanged since iteration 0 (no diff under `lib`, `config` or `priv` in `2f83516..HEAD`); the iteration-0 evidence rows are kept below |
| T11 | Done | `test/whiq_web/controllers/bin_controller_client_ip_test.exs` (new, `async: false`, restores `:client_ip_header` in `on_exit`); spec.md defines client IP for LIM-09/LIM-10 |
| T12 | Done | `test/whiq_web/capture_lock_race_test.exs` (new, sandbox `:auto`, real Bandit, waits on `pg_blocking_pids`, no sleep) |
| T13 | Done | `test/whiq_web/capture_snapshot_chunked_test.exs` + `test/support/short_read_adapter.ex` (one module per file, compiled only in `:test` via `mix.exs:35`) |

The fix iteration touched only tests, `spec.md` (one definition line + traceability) and `tasks.md`. No production code changed. Test integrity: the test diff in `2f83516..HEAD` adds 5 tests and removes none.

---

## Spec-Anchored Acceptance Criteria

Payload/conjunction rule: stored rows are compared by byte content, `body_size` and `body_truncated`. Ring-buffer tests compare the full sorted id set. Broadcasts are compared by the exact mailbox list and order. LiveView assertions read element ids and exact text. The race test asserts the exact status line and the stored-row count.

| AC | Spec-defined outcome | `file:line` + assertion | Result |
| -- | -------------------- | ----------------------- | ------ |
| LIM-01 | Body > 524,288 B: first 524,288 B stored, `body_truncated` true, 200 | Context `test/whiq/inspector_test.exs:246-248` `stored.body == binary_part(body, 0, 524_288)`, `body_truncated == true`, `body_size == 524_288` (524,289 random bytes); ConnTest `test/whiq_web/controllers/capture_controller_test.exs:168-172` `response(conn, 200) == ""` + same three; real Bandit `test/whiq_web/capture_server_test.exs:82-88` 1 MB body, `status_line == "HTTP/1.1 200 OK\r\n"` + same three; snapshot `test/whiq_web/capture_snapshot_test.exs:63` `body == binary_part(body, 0, limit)` (`limit = max + 1`); short-read adapter `test/whiq_web/capture_snapshot_chunked_test.exs:34` 700,000 B in 100,000 B `{:more, ...}` chunks -> `snapshot body == binary_part(body, 0, max + 1)` | PASS |
| LIM-02 | Exactly 524,288 B: stored whole, `body_truncated` false | `test/whiq/inspector_test.exs:257-259` `stored.body == body`, `body_truncated == false`, `body_size == 524_288`; `test/whiq_web/controllers/capture_controller_test.exs:184-187` `response(conn, 200) == ""`, `body == body`, `body_truncated == false`; short-read adapter `test/whiq_web/capture_snapshot_chunked_test.exs:27` 300,000 B in three reads -> `snapshot body == body` (order and bytes) | PASS |
| LIVE-10 | `body_truncated` true -> "Body truncated: showing the first <body_size> bytes" | `test/whiq_web/live/bin_live_test.exs:484` `notice == "Body truncated: showing the first 524288 bytes"`; negative `:492-493` `refute has_element?(view, "#body-truncated")` | PASS |
| LIM-03 | Capture into a bin with 100 stores it and deletes the oldest | `test/whiq/inspector_test.exs:294-295` `stored_ids(bin) == Enum.sort(kept_ids ++ [new_id])`, `refute oldest_id in ...`; just-under `:305-306` 99 + 1 -> all 100 kept, `refute_received {:request_evicted, _}`; other bin untouched `:317` | PASS |
| LIM-04 | 20 concurrent captures into 95 -> exactly 100, the 100 newest | `test/whiq/inspector_concurrency_test.exs:93` `backend_pids |> Enum.uniq() |> length() == 20` (real parallel connections), `:96` `stored_ids(bin) == Enum.sort(newest_seeded ++ new_ids)` | PASS |
| LIM-05 | Eviction broadcast on the bin topic | `test/whiq/inspector_test.exs:327-330` mailbox `== [{:request_captured, %{id: ^new_id}}, {:request_evicted, oldest_id}]` (payload and order) | PASS |
| LIVE-04 | Every open page removes the evicted request | `test/whiq_web/live/bin_live_test.exs:441-445` for two views: `refute has_element?(view, "#requests-#{oldest.id}")`, `length(ids) == 100`, `hd(ids) == "requests-#{latest.id}"` | PASS |
| LIM-06 | 61st capture in the window -> 429, `retry-after` in seconds, nothing stored | Test config limit 2 (`config/test.exs:30`). Just under `test/whiq_web/controllers/capture_controller_test.exs:220-222` two 200s, 2 rows; over `:232-236` `response(conn, 429) == ""`, one `retry-after` header, `Integer.parse` gives `{seconds, ""}` with `seconds >= 1`, still 2 rows; unit `test/whiq/rate_limit_test.exs:11-17` | PASS (prod value 60/60 000 ms checked by inspection at `config/config.exs:18`, see note) |
| LIM-07 | After the window resets, captures are accepted again | `test/whiq/rate_limit_test.exs:35-38` hit until denied with `scale_ms: 1000`, wait `retry_after` s, `check(key, 1, 1_000) == :ok` | PASS |
| LIM-08 | One bin limited, other bins still accepted | `test/whiq_web/controllers/capture_controller_test.exs:254-257` bin A `status == 429`, then bin B `response(..., 200) == ""` and 1 row; unit `test/whiq/rate_limit_test.exs:24-27` | PASS |
| LIM-09 | 11th bin from one client IP within the hour -> no bin, "Too many bins created. Try again later."; client IP = proxy header when valid, else peer (spec line after LIM-10) | Peer path: `test/whiq_web/controllers/bin_controller_test.exs:32-33` first -> bin created (just under); `:37-38` second -> `redirected_to == "/"`, `Bin` count `== 1`; `:48` `#flash-error` text `=~ "Too many bins created. Try again later."`. Proxy-header path: `test/whiq_web/controllers/bin_controller_client_ip_test.exs:49` first POST with `fly-client-ip` from shared peer `172.16.0.1` -> `redirected_to =~ ~r"\A/bins/...\z"`; `:51` repeat of the same header value -> `redirected_to == ~p"/"`; `:52` `Bin` count `== 1` | PASS |
| LIM-10 | One client IP limited, other client IPs still create bins | Peer path: `test/whiq_web/controllers/bin_controller_test.exs:54-59` limited IP redirected to `/`, a second IP -> count `== 2`. Proxy-header path: `test/whiq_web/controllers/bin_controller_client_ip_test.exs:42-44` two distinct `fly-client-ip` values from the same peer -> both `redirected_to =~ ~r"\A/bins/[A-Za-z0-9_-]{32}\z"`, count `== 2` | PASS |
| LIM-11 | Truncation and eviction in the same capture | `test/whiq/inspector_test.exs:340-343` `body == binary_part(body, 0, 524_288)`, `body_truncated == true`, 100 rows, oldest gone | PASS |
| LIM-12 | Rate-limited capture evicts nothing | `test/whiq_web/controllers/capture_controller_test.exs:244-247` full bin (100), `status == 429`, `stored_ids(bin) == full_ids` | PASS |
| LIVE-14 | Selected request evicted -> newest remaining selected | `test/whiq_web/live/bin_live_test.exs:458-460` `#request-detail` present, `detail_path == "/latest"`, `selected_row_ids == ["requests-#{latest.id}-select"]`; unselected eviction keeps the selection `:471-472` | PASS |

**Status**: ✅ All 15 ACs covered on the spec outcome. 0 spec-precision gaps.

**SP-1 closed**: `spec.md` now states, under LIM-10, that "client IP" is the configured proxy header (`fly-client-ip` in prod) when it holds a valid IP, otherwise the peer address (`WhiqWeb.ClientIP`). Both branches are asserted: the peer in `bin_controller_test.exs`, the header with a shared peer in `bin_controller_client_ip_test.exs`. The header-path test does not re-assert the flash text. The text comes from the same deny branch already asserted at `bin_controller_test.exs:48`, and M14 shows the deny branch is discriminated on both paths.

**Note on production limit values** (unchanged from iteration 0): `60 / 60_000 ms` and `10 / 3_600_000 ms` (`config/config.exs:18-19`) are overridden in `config/test.exs:30-31` by design (Out of Scope row: "app config exists so tests can lower them"). They were checked by inspection.

---

## CAP-07 after the rewrite (user-approved change)

The original snapshot test sent 8,000,001 bytes so that `read_body` needed two reads, and asserted that the result was complete. The rewrite asserts only the first `max_body_bytes + 1` bytes (`capture_snapshot_test.exs:63`). Byte-for-byte fidelity is still covered:

- `test/whiq_web/controllers/capture_controller_test.exs:101` 4,096 random bytes stored byte-for-byte (the CAP-07 AC test)
- `test/whiq/inspector_test.exs:246`, `:257`, `capture_controller_test.exs:170`, `:186` 524,288-byte random bodies compared byte-for-byte
- `test/whiq_web/capture_server_test.exs:86` 1 MB random body over real Bandit, first 524,288 bytes compared byte-for-byte
- `test/whiq_web/capture_server_test.exs:53` chunked body de-chunked

What the rewrite lost is coverage of joining several `read_body` reads. The remaining limit (524,289) is smaller than `read_body`'s `:length`, so Plug.Test and Bandit HTTP/1 return it in one call. Bandit HTTP/1 always fills `:length` before it returns `{:more, ...}` (`deps/bandit/lib/bandit/http1/socket.ex:420-425` content-length, `:458-467` chunked). Bandit HTTP/2 can return a short `{:more, ...}` on a read timeout and can overshoot `:length` by one DATA frame (`deps/bandit/lib/bandit/http2/stream.ex:336-369`). So the recursive branch `capture_snapshot.ex:44-45` is reachable only over HTTP/2. Iteration 1 (T13) drives it with `test/support/short_read_adapter.ex`, which hands out preset chunks ignoring `:length`; M16, M17 and the fresh N2 are now killed.

---

---

## Controller 404 when the bin disappears before the lock (design Error Handling)

Covered by T12 in `test/whiq_web/capture_lock_race_test.exs:59-79`. The test process takes a FOR UPDATE row lock on the bin inside `Repo.transact` and sends a raw HTTP/1.1 capture to a real Bandit listener. It polls `pg_locks`/`pg_blocking_pids` (`:36-56`, 5 s deadline, no sleep) until a backend is blocked on its lock, then removes the bin and commits. Assertions: `:77` `{:ok, "HTTP/1.1 404 Not Found\r\n"} = :gen_tcp.recv(...)` and `:78` stored rows for the bin `== 0`. The wait proves the request reached `capture_request/2` (only that function locks bin rows) after the token lookup. So the test hits the intended branch and not the earlier unknown-token 404. Flakiness: 15 isolated runs (`--seed 1..15`) and 4 full-suite runs (precommit + 3), all green.

---

## Discrimination Sensor

Scratch: detached worktree `~/Projects/whiq-verifier-wt` at `174cf8b`, with `_build`, `deps` and `.env` copied. Each mutant was applied alone by exact unique string replacement. The full suite ran with docker compose (project `whiq`, run from the worktree, `mix test`), and each mutant was reverted by checking the mutated file out again from HEAD. The worktree's porcelain status was clean after the last revert, and the worktree was then unregistered and deleted with git worktree (remove, then prune). Real tree: `git status --porcelain` empty before and after, `HEAD` `174cf8b` throughout. Every mutant compiled (no `CompileError`) and ran all 139 tests. Depth: P0-style (storage bounds are a data-integrity path): 4 re-runs of iteration-0 survivors, 4 fresh mutants on the fix areas, 6 re-runs of previously killed critical paths.

| # | File:line | Mutation | Killed by | Result |
| - | --------- | -------- | --------- | ------ |
| M13 | `lib/whiq_web/controllers/bin_controller.ex:11` | key on `conn.remote_ip` instead of `ClientIP.from_conn/1` | `bin_controller_client_ip_test.exs:38`, `:47` | ✅ Killed (was a survivor) |
| M16 | `lib/whiq_web/capture_snapshot.ex:45` | accumulator reversed `[chunk, acc]` | `capture_snapshot_chunked_test.exs:24`, `:30` | ✅ Killed (was a survivor) |
| M17 | `lib/whiq_web/capture_snapshot.ex:45` | stop after the first short `:more` chunk | `capture_snapshot_chunked_test.exs:24`, `:30` | ✅ Killed (was a survivor) |
| M18 | `lib/whiq_web/controllers/capture_controller.ex:17` | `{:error, :not_found}` from `capture_request/2` -> 200 | `capture_lock_race_test.exs:59` | ✅ Killed (was a survivor) |
| N1 | `lib/whiq_web/capture_snapshot.ex:41` | stop guard `>=` -> `>` (keeps reading when exactly at the limit) | `capture_server_test.exs:25`, `:82`, `capture_snapshot_test.exs:29`, `:59` | ✅ Killed (fresh) |
| N2 | `lib/whiq_web/capture_snapshot.ex:39` | final `{:ok, chunk, _}` drops the accumulated chunks | `capture_snapshot_chunked_test.exs:24` | ✅ Killed (fresh) |
| N3 | `lib/whiq/inspector.ex:106` | `if locked` -> `if true` (insert into a vanished bin) | `inspector_test.exs:346`, `capture_lock_race_test.exs:59` | ✅ Killed (fresh) |
| N4 | `lib/whiq_web/capture_snapshot.ex:52` | `cap/2` cuts at `limit - 1` (loses the extra byte) | `capture_snapshot_chunked_test.exs:30`, `capture_snapshot_test.exs:59`, `capture_server_test.exs:69`, `capture_controller_test.exs:159` | ✅ Killed (fresh) |
| M1 | `lib/whiq/inspector.ex:84` | truncation flag `>` -> `>=` | `inspector_test.exs:251`, `capture_controller_test.exs:175`, `bin_live_test.exs:487` | ✅ Killed |
| M3 | `lib/whiq/inspector.ex:113` | cap off-by-one `offset ^(max + 1)` | `inspector_concurrency_test.exs:82`, `inspector_test.exs:288`, `:320`, `:333`, `bin_live_test.exs:433`, `:449` | ✅ Killed |
| M4 | `lib/whiq/inspector.ex:104` | row lock (FOR UPDATE) removed | `inspector_concurrency_test.exs:82`, `capture_lock_race_test.exs:59` | ✅ Killed (now by 2 tests) |
| M9 | `lib/whiq_web/controllers/capture_controller.ex:32` | one global capture key instead of `{:capture, bin.id}` | 25 tests incl. `capture_controller_test.exs:250` | ✅ Killed |
| M14 | `lib/whiq_web/controllers/bin_controller.ex:16` | denied branch still creates a bin | `bin_controller_test.exs:29`, `:51`, `bin_controller_client_ip_test.exs:47` | ✅ Killed |
| M15 | `lib/whiq_web/capture_snapshot.ex:19` | read limit `max` instead of `max + 1` | `capture_snapshot_chunked_test.exs:30`, `capture_snapshot_test.exs:59`, `capture_server_test.exs:69`, `capture_controller_test.exs:159` | ✅ Killed |

The iteration-0 equivalents M22 (`request_count` decrement) and M25 (`cap/2` returns the body uncut) were not re-run. Nothing in their code or tests changed, and their equivalence reasoning still holds. N4 shows that the cut point of `cap/2` itself is now discriminated.

**Result**: 14/14 killed - PASS ✅

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ The fix iteration adds tests and one test adapter only |
| Surgical changes | ✅ Only files named in T11-T13, plus spec/tasks traceability |
| No scope creep | ✅ |
| Matches patterns | ✅ Env save/restore copied from `client_ip_test.exs`; `:auto` sandbox as in `inspector_concurrency_test.exs`; real Bandit harness as in `capture_server_test.exs`; one module per file in `test/support` |
| Spec-anchored outcome check | ✅ Exact status line, byte-for-byte bodies, exact redirect targets and row counts |
| Per-layer Coverage Expectation (tasks.md matrix) | ✅ Context 1:1; controllers happy + over-limit + other-key on both client-IP paths; race 404 at the HTTP level; snapshot single-read and multi-read |
| Every test maps to a spec requirement | ✅ New tests are labelled LIM-01/02/09/10; the race test maps to the design Error Handling row "Bin deleted between lookup and lock -> 404" (T12) |
| Documented guidelines followed: `AGENTS.md` | ✅ No `Process.sleep` in the new tests (the race test polls `pg_locks` with a deadline); `start_supervised!` for Bandit; tests that mutate app env are `async: false`. The iteration-0 exception (`rate_limit_test.exs:36` wall-clock wait) is unchanged |

Observations (non-blocking): the race test's poll loop spins without backoff for up to 5 s. In practice it exits within a few polls, and the deadline bounds it. `unique_client_ip/0` wraps after 65,536 values per run, far beyond any realistic test count.

---

## Edge Cases

- [x] LIM-11 truncation + eviction in one capture: `inspector_test.exs:333`
- [x] LIM-12 rate-limited capture evicts nothing: `capture_controller_test.exs:239`
- [x] LIVE-14 selected request evicted: `bin_live_test.exs:449`
- [x] Bin removed between lookup and lock returns 404 at the HTTP layer: `capture_lock_race_test.exs:77-78` (domain-only in iteration 0)

---

## Gate Check

- **Gate command**: `docker compose run app mix precommit` with `--rm` (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`)
- **Result**: exit 0; 139 tests, 0 failures, 0 skipped (seed 588169, 1.6 s)
- **Repeat runs**: `capture_lock_race_test.exs` 15/15 green (seeds 1-15); full suite 3 more runs, 139/139 each
- **`git status --porcelain` after gate**: empty (`format` changed nothing)
- **Test count before feature** (`5e2bc2f`): 104
- **Test count at iteration 0**: 134
- **Test count after fix iteration**: 139
- **Delta**: +35 over the feature (+5 in the fix iteration)
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans

None. Iteration-0 Fix 1-3 are resolved by T11-T13.

---

## Requirement Traceability Update

The Verifier does not edit `spec.md`. Proposed statuses:

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| LIM-01..08, LIM-11, LIM-12 | Done | ✅ Verified |
| LIVE-04, LIVE-10, LIVE-14 | Done | ✅ Verified |
| LIM-09 | Done (⚠️ peer only at iteration 0) | ✅ Verified |
| LIM-10 | Done (❌ needed a fix at iteration 0) | ✅ Verified |

---

## Lessons

Iteration 1 has no new signal: no surviving mutant, no spec-precision gap, no failed AC, no gate failure. Candidates L-006..L-009 were recorded from iteration 0 of this same feature. Promotion counts distinct features only, so re-adding them from `abuse-limits` would not corroborate them. They stay candidates until another feature reproduces the signal. Nothing was recorded or penalized.

---

## Summary

**Overall**: ✅ Ready

**Spec-anchored check**: 15/15 ACs matched the spec outcome; 0 spec-precision gaps (SP-1 closed)
**Sensor**: 14/14 mutations killed (4 former survivors, 4 fresh, 6 critical-path re-runs)
**Gate**: 139 passed, 0 failed (`mix precommit` exit 0)

**What works**: everything listed in iteration 0, plus three things. The bin-creation limit is keyed on the resolved client IP behind a shared proxy peer. A capture racing a bin removal gets `HTTP/1.1 404 Not Found` with nothing stored. Body reads split across short `{:more, ...}` chunks are joined in order and capped at `max_body_bytes + 1`.

**Issues found**: none.

**Next steps**: the orchestrator marks the LIM-* and LIVE-* requirements Verified and closes the feature.
