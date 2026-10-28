# Abuse Limits Validation

**Result**: FAIL (iteration 0: 15/15 ACs have `file:line` evidence on the spec outcome, build gate green with 134 tests; sensor 25 mutants, 19 killed, 6 survived of which 2 are equivalent and 4 are real; 1 spec-precision gap)

**Date**: 2026-10-28
**Spec**: `.specs/features/abuse-limits/spec.md`
**Diff range**: `5e2bc2f..5af0ee8` (T1 `62631aa`, T2 `858fffb`, T3 `1402fc7`, T4 `4647c64`, T5 `3b7c2e4`, T6 `2480140`, T7 `497d83e`, T8 `008b825`, T9 `c5b6936`, T10 `5af0ee8` on `feat/abuse-limits`)
**Verifier**: independent sub-agent (author != verifier)

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | Done | `priv/repo/migrations/20261028201237_add_body_truncated_to_requests.exs:6` `boolean, null: false, default: false`; `lib/whiq/inspector/captured_request.ex:17` |
| T2 | Done | `lib/whiq/inspector.ex:73-84` stored body cut with `binary_part`, `body_size` from stored bytes, `body_truncated: byte_size(body) > max_body_bytes`; `config/config.exs:15` |
| T3 | Done | `lib/whiq/inspector.ex:100-127` `Repo.transact` + `lock: "FOR UPDATE"`, insert, `delete_all ... offset ^max_requests` ordered `desc: inserted_at, desc: id`; broadcasts after commit `:89-94`; missing bin -> `{:error, :not_found}` `:124` |
| T4 | Done | `lib/whiq/rate_limit.ex:6` `use Hammer, backend: :ets`, `:15-20` `check/3` with `max(1, ceil(ms / 1000))`; `lib/whiq/application.ex:15` started before the endpoint; `mix.exs:76` `== 7.5.0` |
| T5 | Done | `lib/whiq_web/client_ip.ex:8-16` verbatim move of the old `CaptureSnapshot.remote_ip/1` |
| T6 | Done | `lib/whiq_web/capture_snapshot.ex:19-53` bounded read of `max_body_bytes + 1`, no drain; `lib/whiq_web/controllers/capture_controller.ex:17` 404 on `{:error, :not_found}` |
| T7 | Done | `lib/whiq_web/controllers/capture_controller.ex:11-33` rate check after lookup, before `from_conn/1`; 429 + `retry-after` |
| T8 | Done | `lib/whiq_web/controllers/bin_controller.ex:9-20` check `{:bin, ClientIP.from_conn(conn)}`, flash + redirect `/` |
| T9 | Done | `lib/whiq_web/live/bin_live.ex:57-78` `stream_delete_by_dom_id`, count decrement, reselect newest when the selection is evicted |
| T10 | Done | `lib/whiq_web/live/bin_live.ex:226-234` `#body-truncated` notice |

All `Done when` boxes in `tasks.md` are checked. Test integrity: `git diff 5e2bc2f..HEAD -- test` removes two `test "` lines. `BIN-01` is the same test with a new signature (`bin_controller_test.exs:18`). The old `CAP-07` snapshot test (8,000,001 bytes returned whole) was rewritten as the LIM-01 snapshot test (`capture_snapshot_test.exs:59`). The user approved this change; see "CAP-07 after the rewrite" below.

---

## Spec-Anchored Acceptance Criteria

Payload/conjunction rule: stored rows are compared by byte content, `body_size` and `body_truncated`. Ring-buffer tests compare the full sorted id set. Broadcasts are compared by the exact mailbox list and order. LiveView assertions read element ids and exact text.

| AC | Spec-defined outcome | `file:line` + assertion | Result |
| -- | -------------------- | ----------------------- | ------ |
| LIM-01 | Body > 524,288 B: first 524,288 B stored, `body_truncated` true, 200 | Context `test/whiq/inspector_test.exs:246-248` `stored.body == binary_part(body, 0, 524_288)`, `body_truncated == true`, `body_size == 524_288` (524,289 random bytes); ConnTest `test/whiq_web/controllers/capture_controller_test.exs:168-172` `response(conn, 200) == ""` + same three; real Bandit `test/whiq_web/capture_server_test.exs:82-88` 1 MB body, `status_line == "HTTP/1.1 200 OK\r\n"` + same three; snapshot `test/whiq_web/capture_snapshot_test.exs:63` `body == binary_part(body, 0, limit)` (`limit = max + 1`) | PASS |
| LIM-02 | Exactly 524,288 B: stored whole, `body_truncated` false | `test/whiq/inspector_test.exs:257-259` `stored.body == body`, `body_truncated == false`, `body_size == 524_288`; `test/whiq_web/controllers/capture_controller_test.exs:184-187` `response(conn, 200) == ""`, `body == body`, `body_truncated == false` | PASS |
| LIVE-10 | `body_truncated` true -> "Body truncated: showing the first <body_size> bytes" | `test/whiq_web/live/bin_live_test.exs:484` `notice == "Body truncated: showing the first 524288 bytes"`; negative `:492-493` `refute has_element?(view, "#body-truncated")` | PASS |
| LIM-03 | Capture into a bin with 100 stores it and deletes the oldest | `test/whiq/inspector_test.exs:294-295` `stored_ids(bin) == Enum.sort(kept_ids ++ [new_id])`, `refute oldest_id in ...`; just-under `:305-306` 99 + 1 -> all 100 kept, `refute_received {:request_evicted, _}`; other bin untouched `:317` | PASS |
| LIM-04 | 20 concurrent captures into 95 -> exactly 100, the 100 newest | `test/whiq/inspector_concurrency_test.exs:93` `backend_pids |> Enum.uniq() |> length() == 20` (real parallel connections), `:96` `stored_ids(bin) == Enum.sort(newest_seeded ++ new_ids)` | PASS |
| LIM-05 | Eviction broadcast on the bin topic | `test/whiq/inspector_test.exs:327-330` mailbox `== [{:request_captured, %{id: ^new_id}}, {:request_evicted, oldest_id}]` (payload and order) | PASS |
| LIVE-04 | Every open page removes the evicted request | `test/whiq_web/live/bin_live_test.exs:441-445` for two views: `refute has_element?(view, "#requests-#{oldest.id}")`, `length(ids) == 100`, `hd(ids) == "requests-#{latest.id}"` | PASS |
| LIM-06 | 61st capture in the window -> 429, `retry-after` in seconds, nothing stored | Test config limit 2 (`config/test.exs:30`). Just under `test/whiq_web/controllers/capture_controller_test.exs:220-222` two 200s, 2 rows; over `:232-236` `response(conn, 429) == ""`, one `retry-after` header, `Integer.parse` gives `{seconds, ""}` with `seconds >= 1`, still 2 rows; unit `test/whiq/rate_limit_test.exs:11-17` | PASS (prod value 60/60 000 ms checked by inspection at `config/config.exs:18`, see note) |
| LIM-07 | After the window resets, captures are accepted again | `test/whiq/rate_limit_test.exs:35-38` hit until denied with `scale_ms: 1000`, wait `retry_after` s, `check(key, 1, 1_000) == :ok` | PASS |
| LIM-08 | One bin limited, other bins still accepted | `test/whiq_web/controllers/capture_controller_test.exs:254-257` bin A `status == 429`, then bin B `response(..., 200) == ""` and 1 row; unit `test/whiq/rate_limit_test.exs:24-27` | PASS |
| LIM-09 | 11th bin from one IP within the hour -> no bin, "Too many bins created. Try again later." | Test config limit 1 (`config/test.exs:31`). `test/whiq_web/controllers/bin_controller_test.exs:32-33` first -> bin created (just under); `:37-38` second -> `redirected_to == "/"`, `Bin` count `== 1`; `:48` `#flash-error` text `=~ "Too many bins created. Try again later."` on `/` | PASS on peer address; ⚠️ see spec-precision gap SP-1 and M13 |
| LIM-10 | One IP limited, other IPs still create bins | `test/whiq_web/controllers/bin_controller_test.exs:54-59` limited IP redirected to `/`, a second IP -> count `== 2`, redirect `=~ ~r"\A/bins/[A-Za-z0-9_-]{32}\z"` | PASS on peer address; ❌ client IP behind the proxy not covered (M13) |
| LIM-11 | Truncation and eviction in the same capture | `test/whiq/inspector_test.exs:340-343` `body == binary_part(body, 0, 524_288)`, `body_truncated == true`, 100 rows, oldest gone | PASS |
| LIM-12 | Rate-limited capture evicts nothing | `test/whiq_web/controllers/capture_controller_test.exs:244-247` full bin (100), `status == 429`, `stored_ids(bin) == full_ids` | PASS |
| LIVE-14 | Selected request evicted -> newest remaining selected | `test/whiq_web/live/bin_live_test.exs:458-460` `#request-detail` present, `detail_path == "/latest"`, `selected_row_ids == ["requests-#{latest.id}-select"]`; unselected eviction keeps the selection `:471-472` | PASS |

**Status**: All 15 ACs have evidence on the spec outcome. LIM-09 and LIM-10 are discriminated only for the peer address. The spec says "client IP" without defining it (SP-1), and the proxy-header path that design.md requires for bin creation is untested (M13).

**Spec-precision gaps**

- **SP-1 (LIM-09, LIM-10)**: "client IP" is not defined in this spec. `design.md` (WhiqWeb.ClientIP, Risks row 3) defines it as the configured proxy header (`fly-client-ip`) when it holds a valid IP, otherwise the peer address. The spec ACs do not pin this, so the tests key on `conn.remote_ip` only, and the main production risk is unasserted: behind Fly every client would share the proxy's bucket.

**Note on production limit values**: `60 / 60_000 ms` and `10 / 3_600_000 ms` (`config/config.exs:18-19`) are overridden in `config/test.exs:30-31` by design ("app config exists so tests can lower them"). The values were checked by inspection. No test discriminates them, which is the accepted trade-off of the Out of Scope row. Body and request caps keep their real values in test, and the tests assert 524,288 and 100 directly.

---

## CAP-07 after the rewrite (user-approved change)

The original snapshot test sent 8,000,001 bytes so that `read_body` needed two reads, and asserted that the result was complete. The rewrite asserts only the first `max_body_bytes + 1` bytes (`capture_snapshot_test.exs:63`). Byte-for-byte fidelity is still covered:

- `test/whiq_web/controllers/capture_controller_test.exs:101` 4,096 random bytes stored byte-for-byte (the CAP-07 AC test)
- `test/whiq/inspector_test.exs:246`, `:257`, `capture_controller_test.exs:170`, `:186` 524,288-byte random bodies compared byte-for-byte
- `test/whiq_web/capture_server_test.exs:86` 1 MB random body over real Bandit, first 524,288 bytes compared byte-for-byte
- `test/whiq_web/capture_server_test.exs:53` chunked body de-chunked

What the rewrite lost is coverage of joining several `read_body` reads. The remaining limit (524,289) is smaller than `read_body`'s `:length`, so Plug.Test and Bandit HTTP/1 return it in one call. Bandit HTTP/1 always fills `:length` before it returns `{:more, ...}` (`deps/bandit/lib/bandit/http1/socket.ex:420-425` content-length, `:458-467` chunked). Bandit HTTP/2 can return a short `{:more, ...}` on a read timeout and can overshoot `:length` by one DATA frame (`deps/bandit/lib/bandit/http2/stream.ex:336-369`). So the recursive branch `capture_snapshot.ex:44-45` is reachable only over HTTP/2, and it is not exercised by any test (M16, M17 survived).

---

## Controller 404 when the bin disappears before the lock (author-flagged)

`lib/whiq_web/controllers/capture_controller.ex:17` maps `{:error, :not_found}` from `capture_request/2` to 404. The domain behaviour is tested: `test/whiq/inspector_test.exs:351-353` returns `{:error, :not_found}`, stores nothing and broadcasts nothing. The controller branch is not tested. M18 (404 -> 200) survived. Before this feature, the same race would have raised in the insert (foreign key) and returned 500, so the mapping is new behaviour from the design.md Error Handling row "Bin deleted between lookup and lock -> 404". The risk is small (a 1-line branch on a sub-millisecond race), but under evidence-or-zero it is uncovered. A deterministic test needs a seam: for example a real-server test in which the test process holds `SELECT ... FOR UPDATE` on the bin in its own transaction, sends the capture, deletes the bin and commits, then asserts `HTTP/1.1 404`. Alternatively the user can explicitly accept the risk.

---

## Discrimination Sensor

The sensor ran in a detached worktree at `5af0ee8` (`~/Projects/whiq-verifier-wt`, with `_build`, `deps` and `.env` copied). One mutant was applied at a time, then `docker compose -p whiq run --rm app mix test` ran from the worktree, which mounts only the worktree. Each mutant was reverted with `git checkout -- <file>`, and the worktree was removed afterwards. Every mutant compiled and ran the full 134-test suite. The real tree's `git status --porcelain` was empty before and after, and `HEAD` stayed at `5af0ee8`. Depth: P0-style (≥5 mutations; storage bounds are a data-integrity path), 25 manual mutants.

| # | File:line | Mutation | Killed by | Result |
| - | --------- | -------- | --------- | ------ |
| M1 | `lib/whiq/inspector.ex:84` | `>` -> `>=` (truncation boundary) | `inspector_test.exs:251`, `capture_controller_test.exs:175`, `bin_live_test.exs:487` | Killed |
| M2 | `lib/whiq/inspector.ex:74` | store `max - 1` bytes | 7 tests incl. `inspector_test.exs:240`, `capture_server_test.exs:69`, `bin_live_test.exs:477` | Killed |
| M3 | `lib/whiq/inspector.ex:113` | cap off-by-one `offset ^(max + 1)` | `inspector_concurrency_test.exs:82`, `inspector_test.exs:288`, `:320`, `:333`, `bin_live_test.exs:433`, `:449` | Killed |
| M4 | `lib/whiq/inspector.ex:104` | `FOR UPDATE` removed | `inspector_concurrency_test.exs:82` | Killed |
| M5 | `lib/whiq/inspector.ex:112` | evict newest (`asc`) | same 6 as M3 | Killed |
| M6 | `lib/whiq/inspector.ex:93` | eviction broadcast removed | `inspector_test.exs:320`, `bin_live_test.exs:433`, `:449` | Killed |
| M7 | `lib/whiq/inspector.ex:90-94` | evicted broadcast before captured | `inspector_test.exs:320` | Killed |
| M8 | `lib/whiq/rate_limit.ex:18` | `retry_after = div(ms, 1000)` (floor, may be 0) | `rate_limit_test.exs:32` | Killed |
| M9 | `lib/whiq_web/controllers/capture_controller.ex:32` | one global key instead of `{:capture, bin.id}` | 23 tests incl. `capture_controller_test.exs:250` | Killed |
| M10 | `lib/whiq_web/controllers/capture_controller.ex:25` | `retry-after` header removed | `capture_controller_test.exs:225` | Killed |
| M11 | `lib/whiq_web/controllers/capture_controller.ex:23` | denied capture still read and stored before 429 | `capture_controller_test.exs:225`, `:239` | Killed |
| M12 | `lib/whiq_web/controllers/bin_controller.ex:11` | one global key instead of `{:bin, ip}` | `bin_controller_test.exs:29`, `:51` | Killed |
| M13 | `lib/whiq_web/controllers/bin_controller.ex:11` | key on `conn.remote_ip` instead of `ClientIP.from_conn/1` (ignores `fly-client-ip`) | none | **Survived** |
| M14 | `lib/whiq_web/controllers/bin_controller.ex:16` | denied branch still creates a bin | `bin_controller_test.exs:29`, `:51` | Killed |
| M15 | `lib/whiq_web/capture_snapshot.ex:19` | read limit `max` instead of `max + 1` | `capture_server_test.exs:69`, `capture_snapshot_test.exs:59`, `capture_controller_test.exs:159` | Killed |
| M16 | `lib/whiq_web/capture_snapshot.ex:45` | accumulator reversed `[chunk, acc]` | none | **Survived** (HTTP/2-only path) |
| M17 | `lib/whiq_web/capture_snapshot.ex:44-45` | stop after the first short `:more` chunk | none | **Survived** (HTTP/2-only path) |
| M18 | `lib/whiq_web/controllers/capture_controller.ex:17` | `{:error, :not_found}` -> 200 | none | **Survived** (author-flagged) |
| M19 | `lib/whiq_web/live/bin_live.ex:60` | `stream_delete_by_dom_id` removed | `bin_live_test.exs:433`, `:449` | Killed |
| M20 | `lib/whiq_web/live/bin_live.ex:65` | never reselect on eviction | `bin_live_test.exs:449` | Killed |
| M21 | `lib/whiq_web/live/bin_live.ex:73` | new selection not re-inserted (no highlight) | `bin_live_test.exs:449` | Killed |
| M22 | `lib/whiq_web/live/bin_live.ex:61` | `request_count` decrement removed | none | Survived: **equivalent** (count only drives the empty state `== 0`, and eviction runs only at 100 rows) |
| M23 | `lib/whiq_web/live/bin_live.ex:227` | notice always shown | `bin_live_test.exs:487` | Killed |
| M24 | `lib/whiq_web/live/bin_live.ex:233` | notice shows a size other than `body_size` | `bin_live_test.exs:477` | Killed |
| M25 | `lib/whiq_web/capture_snapshot.ex:52` | `cap/2` returns the body uncut | none | Survived: **equivalent** at the spec level (`Inspector` cuts at `max` and flags `size > max` anyway; reachable only via HTTP/2 overshoot) |

**Result**: 19/25 killed, 2 equivalent, **4 real survivors (M13, M16, M17, M18)** - FAIL

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ No features beyond the spec; `cap/2` is a small defensive guard for adapters that overshoot `:length` (real for Bandit HTTP/2) |
| Surgical changes | ✅ Only files named in tasks.md, plus config and lock |
| No scope creep | ✅ |
| Matches patterns | ✅ Context owns domain rules; controllers own HTTP; LiveView by element id; `@impl true` on the first `handle_info/2` clause covers the new clause |
| Spec-anchored outcome check | ⚠️ All ACs asserted on exact values; SP-1 flagged |
| Per-layer Coverage Expectation (tasks.md matrix) | ⚠️ Context 1:1 to LIM-01..05, LIM-11 ✅; limiter ✅; controllers happy + over-limit + other-key ✅, but bin creation behind the proxy header (M13) and controller 404 on the race (M18) are missing |
| Every test maps to a spec requirement | ✅ Unlabelled tests map to design/Done-when: `inspector_test.exs:309` (eviction scoped to bin), `:346` (deleted bin), `bin_live_test.exs:463` (T9 Done-when), `client_ip_test.exs` (T5), `rate_limit_test.exs:20` (T4) |
| Documented guidelines followed: `AGENTS.md` | ✅ with one justified exception: `rate_limit_test.exs:36` uses `Process.sleep/1` to wait out a wall-clock window (Hammer takes no injected clock, design.md Risks row 4). This is not process synchronization, which is the case the guideline forbids |

---

## Edge Cases

- [x] LIM-11 truncation + eviction in one capture: `inspector_test.exs:333`
- [x] LIM-12 rate-limited capture evicts nothing: `capture_controller_test.exs:239`
- [x] LIVE-14 selected request evicted: `bin_live_test.exs:449`
- [ ] Bin deleted between lookup and lock returns 404 at the HTTP layer (design Error Handling): domain only (`inspector_test.exs:346`), controller untested (M18)

---

## Gate Check

- **Gate command**: `docker compose run --rm app mix precommit` (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`)
- **Result**: exit 0; 134 tests, 0 failures, 0 skipped (seed 856850, 1.6 s)
- **`git status --porcelain` after gate**: empty (`format` changed nothing)
- **Test count before feature** (`5e2bc2f`): 104
- **Test count after feature**: 134
- **Delta**: +30
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans

### Fix 1: Bin-creation limit keyed on the proxy client IP (M13, SP-1) - Major

- **Root cause**: The tests set only `conn.remote_ip`, and `:client_ip_header` is unset in test. So keying on the peer address instead of `ClientIP.from_conn/1` cannot be told apart. In production behind Fly, that regression would put all users into one 10/hour bucket.
- **Fix task**: Add a test module with `async: false` (it mutates app env, as in `client_ip_test.exs`) that sets `:client_ip_header` to `"fly-client-ip"` and sends every POST from the same peer `remote_ip`. (a) Two different valid `fly-client-ip` values both create bins. (b) The same header value is limited on its second POST. Optionally add one clause to the spec to pin "client IP" for LIM-09/LIM-10 as the CAP-13/CAP-20 rule.
- **Done when**: M13 is killed.

### Fix 2: Controller 404 when the bin vanishes before the lock (M18) - Minor

- **Root cause**: The race branch at `capture_controller.ex:17` has no HTTP-level test.
- **Fix task**: Real-server test in `capture_server_test.exs`. The test process holds `SELECT ... FOR UPDATE` on the bin in its own transaction (outside the shared sandbox, or in `:auto` mode as in `inspector_concurrency_test.exs`), then sends the capture, deletes the bin, commits, and asserts the status line `HTTP/1.1 404` and no stored row. Alternatively, record an explicit user waiver.
- **Done when**: M18 is killed or waived by the user.

### Fix 3: Multi-read accumulation in `CaptureSnapshot` (M16, M17) - Minor

- **Root cause**: After the cap, a single `read_body` call satisfies Plug.Test and Bandit HTTP/1, so the recursive branch `capture_snapshot.ex:44-45` (reachable on Bandit HTTP/2 short reads) is never exercised. The old CAP-07 8 MB test was the only one that crossed reads.
- **Fix task**: Snapshot unit test with a minimal test `Plug.Conn.Adapter` whose `read_req_body/2` returns `{:more, ...}` in small chunks (for example 100 KB). Assert that the snapshot body equals the first `max + 1` bytes of a random body larger than the cap, and equals the whole body for one under the cap. Alternatively, drop the branch if HTTP/2 is out of scope (needs a user decision).
- **Done when**: M16 and M17 are killed.

---

## Requirement Traceability Update

The Verifier does not edit `spec.md`. Proposed statuses:

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| LIM-01..08, LIM-11, LIM-12 | Done | ✅ Verified |
| LIVE-04, LIVE-10, LIVE-14 | Done | ✅ Verified |
| LIM-09 | Done | ⚠️ Verified on peer address; needs Fix 1 |
| LIM-10 | Done | ❌ Needs Fix (Fix 1) |

---

## Summary

**Overall**: ❌ Not Ready

**Spec-anchored check**: 15/15 ACs with evidence on the spec outcome; 1 spec-precision gap (SP-1, LIM-09/LIM-10 "client IP")
**Sensor**: 19/25 killed, 2 equivalent, 4 real survivors (M13, M16, M17, M18)
**Gate**: 134 passed, 0 failed (`mix precommit` exit 0)

**What works**: Truncation boundary at exactly 524,288 / 524,289 bytes at every layer, including real Bandit. The ring buffer cap, eviction order and row lock hold under 20 real parallel connections. The eviction broadcast payload and order are correct. The per-bin capture limit is tested with 429, `retry-after` >= 1 and no storage or eviction on deny. The per-key bin limit works. LiveView removes evicted rows from every open page, reselects the newest remaining request and shows the truncation notice.

**Issues found**: Fix 1 (Major): the bin limit is not discriminated on the proxy client IP. Fix 2 (Minor): the controller 404 race branch is untested. Fix 3 (Minor): multi-read body accumulation is untested.

**Next steps**: Route Fix 1-3 to an implementer, or get user waivers for Fix 2 and Fix 3. Then re-verify (iteration 1 of 3).
