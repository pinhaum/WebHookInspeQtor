# Request Capture Validation

**Result**: PASS (after fix iteration 1 of 3: 21/21 ACs discriminated on the spec outcome, gate green with 70 tests, 0 real surviving mutants; 3 spec-precision gaps kept as non-blocking)

**Date**: 2026-10-28
**Spec**: `.specs/features/request-capture/spec.md`
**Diff range**: `d7d2aea..25e8342` (`ed2cbf6` docs, then T1 `9a17141`, T2 `4cefa3b`, T3 `9110787`, T4 `58095bd`, T5 `378aa23`, T6 `0a53945`, T7 `5f3f696`, fix `25e8342` on `feat/request-capture`)
**Verifier**: independent sub-agent (author != verifier)

---

## Re-verification log

| Iteration | Commit | Gap addressed | Outcome |
| --------- | ------ | ------------- | ------- |
| 0 | `5f3f696` | - | FAIL: M10 (hardcoded peer fallback) and M15 (method upcased) survived |
| 1 | `25e8342` `test(capture): discriminate peer address fallback and method case` | Fix 1 / M10, Fix 2 / M15 | M10 and M15 killed; spot-check M1, M9, M13 still killed -> PASS |

Iteration 1 judgment: `git diff 5f3f696..25e8342` touches only `test/whiq_web/capture_snapshot_test.exs` and `test/whiq_web/capture_server_test.exs`; no file under `lib`, `config` or `priv` changed.
- Fix 1: `test/whiq_web/capture_snapshot_test.exs:26` `defp peer(conn), do: %{conn | remote_ip: {198, 51, 100, 9}}`. CAP-14 (`:76`) and both CAP-20 tests (`:82`, `:90`) now assert `"198.51.100.9"`, a value that only `conn.remote_ip` can produce. The CAP-14 test still sends a valid `fly-client-ip` header while none is configured, so it also proves the header is ignored.
- Fix 2: `test/whiq_web/capture_server_test.exs:57-66` sends a raw `propfind` request to the real Bandit listener. It asserts the status line `== "HTTP/1.1 200 OK\r\n"` (`:64`) and `[%CapturedRequest{method: "propfind"}] = stored_requests(bin)` (`:65`).
- The optional IPv6 `"::1"` case was not added. That is acceptable: M10 is killed without it, and `:inet.ntoa/1` formatting is library behavior.

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | Done | `priv/repo/migrations/20261028172218_create_requests.exs` (FK `on_delete: :delete_all`, `[:bin_id, :inserted_at]` index), `lib/whiq/inspector/captured_request.ex`, `has_many :requests` in `lib/whiq/inspector/bin.ex:14` |
| T2 | Done | `lib/whiq/inspector.ex:43` `fetch_live_bin_by_capture_token/1` over private `fetch_live_bin/2` (`:74`) |
| T3 | Done | `lib/whiq/inspector.ex:53` `capture_request/2` |
| T4 | Done | `lib/whiq_web/capture_snapshot.ex:13` `from_conn/1` |
| T5 | Done | `lib/whiq_web/controllers/capture_controller.ex:8` |
| T6 | Done | `test/whiq_web/capture_server_test.exs`, `config/test.exs:27` `capture_read_timeout: 200` |
| T7 | Done | `config/runtime.exs:77` `config :whiq, :client_ip_header, "fly-client-ip"`, inside the `config_env() == :prod` block (checked by reading) |
| Fix (iter 1) | Done | `25e8342`, tests only |

T5 test-count correction (planned 19 -> 18) checked. The T5 Done-when list sums to 18: 1 (CAP-01) + 4 (CAP-02) + 1 + 1 (CAP-03, CAP-04) + 1 (CAP-05) + 1 (CAP-06) + 1 (CAP-07) + 3 (CAP-09) + 1 (CAP-10) + 1 (CAP-11+12) + 3 (CAP-16..18). `test/whiq_web/controllers/capture_controller_test.exs` has exactly those 18 tests. This was an arithmetic slip, not a dropped test.

Each old `tok123` routing test (`git show d7d2aea:test/whiq_web/controllers/capture_controller_test.exs`) has a replacement. Every replacement is stronger: it asserts the stored row instead of `conn.private.phoenix_controller`.

| Old test | Replaced by |
| -------- | ----------- |
| body reaches controller unparsed and readable | CAP-09 JSON `capture_controller_test.exs:125-132` + CAP-07 `:94-101` (stored raw bytes) |
| HEAD keeps its method | CAP-02 HEAD `:36-41` |
| POST with `_method=DELETE` keeps its method | CAP-02 `:57-65` (method `"POST"` and body `"_method=DELETE"`) |
| sub-path under the token reaches the controller | CAP-03 `:68-72` (`/github/push`) |
| non-standard method reaches the controller | CAP-02 PROPFIND `:50-55` |
| XML Accept header answered 200 | CAP-01 `:24-33` (same `accept: application/xml` GET, 200 `""` + one row) |

---

## Spec-Anchored Acceptance Criteria

Payload/conjunction rule: every stored-row field is asserted on its value, not just on its presence. The fields are `bin_id`, `method`, `path`, `query_string`, `headers`, `body`, `body_size`, `content_type`, `remote_ip` and `inserted_at` precision. Rows are read back in two ways:
- with `Repo.get!` (`test/whiq/inspector_test.exs:165-168`, `:170-183`);
- with `Repo.one!` by `bin_id` (`test/whiq_web/controllers/capture_controller_test.exs:16-18`), which also enforces "exactly one row".

| AC | Spec-defined outcome | `file:line` + assertion | Result |
| -- | -------------------- | ----------------------- | ------ |
| CAP-01 | Exactly one stored request for the bin; 200 with empty body | `test/whiq_web/controllers/capture_controller_test.exs:31` `response(conn, 200) == ""`; `:32` `%CapturedRequest{method: "GET"} = stored_request(bin)` (`Repo.one!` raises on 0 or >1 rows, `:17`) | PASS |
| CAP-02 | Method recorded exactly as sent, incl. HEAD, OPTIONS, PROPFIND | `test/whiq_web/controllers/capture_controller_test.exs:40` `== "HEAD"`, `:47` `== "OPTIONS"`, `:54` `== "PROPFIND"`, `:63` `== "POST"` with `_method=DELETE`; `test/whiq_web/capture_snapshot_test.exs:34` `.method == "PROPFIND"`; case kept over real HTTP: `test/whiq_web/capture_server_test.exs:65` `[%CapturedRequest{method: "propfind"}] = stored_requests(bin)` | PASS (iter 1) |
| CAP-03 | `/h/:token/github/push` -> path `/github/push` | `test/whiq_web/controllers/capture_controller_test.exs:71` `stored_request(bin).path == "/github/push"`; `test/whiq_web/capture_snapshot_test.exs:38` `== "/github/push"`, `:39` `/a%20b` -> `"/a%20b"` | PASS (encoding: spec-precision gap 1) |
| CAP-04 | No subpath -> path `/` | `test/whiq_web/controllers/capture_controller_test.exs:77` `.path == "/"`; `test/whiq_web/capture_snapshot_test.exs:43` `.path == "/"` | PASS |
| CAP-05 | Query string raw, not decoded or reordered | `test/whiq_web/controllers/capture_controller_test.exs:83` `.query_string == "b=2&a=%20&a=1"`; `test/whiq_web/capture_snapshot_test.exs:47` `== "b=2&a=%20"` | PASS |
| CAP-06 | Every header pair, in received order (AD-008: flat `[n1, v1, ...]`, obs-text bytes OK) | `test/whiq/inspector_test.exs:191` `stored.headers == ["x-a", "1", "x-b", "2", "x-a", "3"]`; `:200` `== ["x-raw", <<0xFF, 0x80>>]`; `test/whiq_web/capture_snapshot_test.exs:56` order kept; `test/whiq_web/controllers/capture_controller_test.exs:91` end to end | PASS |
| CAP-07 | Body byte-for-byte, incl. non-UTF-8 | `test/whiq/inspector_test.exs:209` `stored.body == body` (1024 random bytes); `test/whiq_web/controllers/capture_controller_test.exs:101` (4096 random bytes); `test/whiq_web/capture_snapshot_test.exs:62` 8 000 001-byte body complete (two `read_body` reads) | PASS |
| CAP-08 | Chunked body stored complete and de-chunked | `test/whiq_web/capture_server_test.exs:52` `status_line == "HTTP/1.1 200 OK\r\n"`; `:53` `[%CapturedRequest{body: "hello world"}] = stored_requests(bin)` (3 chunks over raw TCP to real Bandit) | PASS |
| CAP-09 | multipart / urlencoded / JSON stored as raw bytes, unparsed | `test/whiq_web/controllers/capture_controller_test.exs:112`, `:122`, `:132` `stored_request(bin).body == body` | PASS |
| CAP-10 | `Content-Encoding: gzip` -> compressed bytes stored | `test/whiq_web/controllers/capture_controller_test.exs:144` `.body == :zlib.gzip(...)` | PASS |
| CAP-11 | `body_size` == byte size of stored body | `test/whiq/inspector_test.exs:217` `body_size == 2` for `"é"`; `test/whiq_web/controllers/capture_controller_test.exs:154` `== 4` for `"olá"` (multibyte, so byte size != char count) | PASS |
| CAP-12 | `content_type` from `content-type` header; nil when absent | `test/whiq/inspector_test.exs:226` `== "text/plain; a=b"`, `:227` `== nil`; `test/whiq_web/controllers/capture_controller_test.exs:155` `== "text/plain; charset=utf-8"` | PASS (duplicate header: spec-precision gap 3) |
| CAP-13 | Configured client IP header -> its value is `remote_ip` | `test/whiq_web/capture_snapshot_test.exs:70` `remote_ip == "203.0.113.7"` with `fly-client-ip` configured; prod wiring `config/runtime.exs:77` (read, not executed) | PASS |
| CAP-14 | No header configured -> socket peer address | `test/whiq_web/capture_snapshot_test.exs:76` `remote_ip == "198.51.100.9"` (peer set by `peer/1` at `:26`; a valid `fly-client-ip` is present but not configured, so it is ignored) | PASS (iter 1) |
| CAP-15 | `Inspector` takes a plain map, no `Plug.Conn` | `test/whiq/inspector_test.exs:233-235` `assert_raise FunctionClauseError` on `Plug.Test.conn/3`; `:237` row count `== 0`; `lib/whiq/inspector.ex` has no `Plug` reference | PASS |
| CAP-16 | Unknown token -> 404, nothing stored | `test/whiq_web/controllers/capture_controller_test.exs:165` `response(conn, 404) == ""`, `:166` `stored_count() == 0`; context `test/whiq/inspector_test.exs:107-108` `== {:error, :not_found}`, `:129` malformed + `:132` `refute_received :repo_query` | PASS |
| CAP-17 | Expired bin -> 404, nothing stored | `test/whiq_web/controllers/capture_controller_test.exs:178-179`; `test/whiq/inspector_test.exs:140` | PASS |
| CAP-18 | View token under `/h/` -> 404, nothing stored | `test/whiq_web/controllers/capture_controller_test.exs:188-189`; `test/whiq/inspector_test.exs:146` | PASS |
| CAP-19 (edge) | Body read timeout -> 408, nothing stored | `test/whiq_web/capture_server_test.exs:77` `"HTTP/1.1 408 " <> _ = status_line(socket)`; `:81` `stored_requests(bin) == []` (real Bandit, `content-length: 10`, 3 bytes sent; no `Process.sleep`, waits on socket close `:79`) | PASS |
| CAP-20 (edge) | Configured header absent or not an IP -> socket peer | `test/whiq_web/capture_snapshot_test.exs:82` absent -> `"198.51.100.9"`; `:90` `"not-an-ip"` -> `"198.51.100.9"` | PASS (iter 1) |
| CAP-21 (edge) | Empty body -> empty binary, `body_size` 0 | `test/whiq/inspector_test.exs:245` `stored.body == ""`, `:246` `body_size == 0`; `test/whiq_web/capture_snapshot_test.exs:94` `.body == ""` | PASS |

**Status**: 21/21 ACs matched the spec outcome with discriminating tests. There are 3 spec-precision gaps (below); they are non-blocking because the implementation and tests pin the fidelity-consistent reading.

---

## Discrimination Sensor

Isolation:
- Each run used a temporary `git worktree add --detach` at the HEAD of that iteration (`5f3f696` for iter 0, `25e8342` for iter 1).
- The worktree was placed at `/home/gabriel.eurich@koch.intranet/Projects/whiq-verifier-wt`, outside the repo. The session scratchpad `/tmp` path is private to the session and invisible to the Docker daemon.
- `deps`, `_build` and `.env` were copied into the worktree.
- A script applied one mutant at a time and reverted it with `git checkout -- <file>`.
- Each mutant ran the full suite via `docker compose -p whiq run --rm app mix test` (shared `db`, sandboxed).
- After each run the worktree was removed with `git worktree remove --force` + `git worktree prune`.
- Real-tree `git status --porcelain` matched its baseline in both iterations. Iter 0: empty before and after. Iter 1: only `?? .specs/features/request-capture/validation.md`, this report, before and after.

| # | File:line | Mutation | Iter 0 (`5f3f696`) | Iter 1 (`25e8342`) | Killing test(s) |
| - | --------- | -------- | ------------------ | ------------------ | --------------- |
| M1 | `lib/whiq/inspector.ex:66` | Flatten as `[value, name]` | Killed (4) | Killed (4) | `inspector_test.exs` CAP-06 x2, full-field test; controller CAP-06 |
| M2 | `lib/whiq/inspector.ex:66` | Flatten `Enum.reverse(headers)` | Killed (3) | not re-run | `inspector_test.exs` CAP-06, full-field; controller CAP-06 |
| M3 | `lib/whiq/inspector.ex:68` | `body_size: String.length(body)` | Killed (2) | not re-run | `inspector_test.exs` CAP-11; controller CAP-11+12 |
| M4 | `lib/whiq/inspector.ex:69` | Missing `content-type` -> `""` instead of nil | Killed (1) | not re-run | `inspector_test.exs` CAP-12 |
| M5 | `lib/whiq/inspector.ex:44` | Capture lookup keyed by `:view_token` | Killed (20) | not re-run | `inspector_test.exs` capture-token + CAP-18; all controller happy paths; CAP-08, CAP-19 |
| M6 | `lib/whiq/inspector.ex:79` | Drop `expires_at > ^now` | Killed (4) | not re-run | `inspector_test.exs` CAP-17, BIN-10; controller CAP-17; `bin_live_test` BIN-10 |
| M7 | `lib/whiq_web/capture_snapshot.ex:40` | No subpath -> `""` instead of `"/"` | Killed (2) | not re-run | snapshot CAP-04; controller CAP-04 |
| M8 | `lib/whiq_web/capture_snapshot.ex:41` | `URI.decode` the subpath | Killed (1) | not re-run | snapshot CAP-03 (`/a%20b`) |
| M9 | `lib/whiq_web/capture_snapshot.ex:33` | `{:more, ...}` stops after first chunk | Killed (1) | Killed (1) | snapshot CAP-07 (8 000 001 bytes) |
| M10 | `lib/whiq_web/capture_snapshot.ex:51` | Fallback returns hardcoded `"127.0.0.1"` instead of `conn.remote_ip` | Survived | Killed (3) | snapshot CAP-14 (`:76`), CAP-20 absent (`:82`), CAP-20 not-an-ip (`:90`) |
| M11 | `lib/whiq_web/capture_snapshot.ex:48` | Skip `:inet.parse_strict_address/1` | Killed (1) | not re-run | snapshot CAP-20 `"not-an-ip"` |
| M12 | `lib/whiq_web/capture_snapshot.ex:19` | `URI.decode(conn.query_string)` | Killed (2) | not re-run | snapshot CAP-05; controller CAP-05 |
| M13 | `lib/whiq_web/controllers/capture_controller.ex:16` | 404 branch answers 200 | Killed (3) | Killed (3) | controller CAP-16, CAP-17, CAP-18 |
| M14 | `lib/whiq_web/controllers/capture_controller.ex:12` | Remove `Inspector.capture_request/2` call | Killed (16) | not re-run | all controller store tests; CAP-08 |
| M15 | `lib/whiq_web/capture_snapshot.ex:17` | `method: String.upcase(conn.method)` | Survived | Killed (1) | `capture_server_test.exs` "CAP-02: a lowercase method is stored with its case" (`:65`) |
| M16 | `lib/whiq_web/capture_snapshot.ex:20` | `Enum.sort(conn.req_headers)` | Killed (2) | not re-run | snapshot CAP-06; controller CAP-06 |

Production code is byte-identical between `5f3f696` and `25e8342`, so the iteration-0 kills that were not re-run still hold. Iteration 1 re-ran the two survivors plus a spot check of M1, M9 and M13, which cover the context, the snapshot and the controller.

**Sensor depth**: P0-full (manual, 16 mutants covering every branch of the new code; this is the product's core data path)
**Sensor outcome**: 16/16 killed after iteration 1 (iteration 1 re-ran 5: M10, M15, M1, M9, M13, all killed)

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | OK - 2 public context functions, 1 snapshot module, controller action with 2 branches |
| Surgical changes | OK - only files listed in tasks.md (plus `config/test.exs`, planned in T6); fix commit touches only the two test files |
| No scope creep | OK - no limits, broadcast or custom responses |
| Matches patterns | OK - context boundary kept (AD-004: no `Plug` in `Whiq.Inspector`), no cast changeset for programmatic fields (AGENTS.md), shared `fetch_live_bin/2` reuses the zero-query token guard |
| Spec-anchored outcome check | OK - 21/21 |
| Per-layer coverage (context 1:1; routes happy+edge+error) | OK - context covers CAP-06/07/11/12/15/16/17/18/21 1:1; `/h/:token[/*path]` has happy paths per method/content type and all three 404 paths; real server covers CAP-02 case, CAP-08, CAP-19 |
| Every test maps to a requirement | OK - tests not claimed by an AC map to a Done-when item: capture-token happy lookup (`test/whiq/inspector_test.exs:98`) and full-field store (`:170`) |
| Guidelines followed: `AGENTS.md` | OK - `start_supervised!` for Bandit, no `Process.sleep` (socket recv/close used), `async: false` where app env or shared sandbox is touched, env restored in `on_exit` |

Advisory (non-blocking): `read_full_body/2` (`lib/whiq_web/capture_snapshot.ex:28`) has no `{:error, _}` clause. The 408 relies on Bandit raising its own request-timeout error; design.md's diagram documents this, and CAP-19 proves it over real HTTP. With another adapter, an `{:error, :timeout}` would surface as `CaseClauseError` -> 500. This is acceptable for the chosen adapter and is not counted as a gap.

---

## Edge Cases

- [x] CAP-19 read timeout -> 408, zero rows (real Bandit, `test/whiq_web/capture_server_test.exs:68-82`)
- [x] CAP-20 configured header absent / not an IP -> peer address `"198.51.100.9"` (M10, M11 killed)
- [x] CAP-21 empty body -> `""` and `body_size` 0 (context and snapshot)
- [x] Malformed capture token -> not found with zero repo queries (`test/whiq/inspector_test.exs:111-133`)

---

## Gate Check

- **Gate command**: `docker compose run --rm app mix precommit` in the real tree at `25e8342`. Exit 0. It runs `compile --warnings-as-errors`, `deps.unlock --unused`, `format` (only this report untracked afterwards) and `test`.
- **Test run**: 70 tests, 0 failures, 0 skipped. The scratch worktree also gave 70/0 before mutation.
- **Test count before feature**: 31 (tasks.md baseline)
- **Test count after feature**: 70 (69 at `5f3f696` + 1 from fix `25e8342`)
- **Delta**: +39 = T2 5 + T3 8 + T4 11 + T5 (18 - 6 replaced) + T6 2 + fix 1
- **Skipped tests**: none
- **Failures**: none

---

## Spec-Precision Gaps (non-blocking)

1. **CAP-03 path encoding.** The spec says "record the path `/github/push`" but does not say whether a percent-encoded subpath is stored raw or decoded. The implementation and tests store it raw (`test/whiq_web/capture_snapshot_test.exs:39`, `/a%20b`), consistent with CAP-05 and the fidelity goal. Recommend stating "raw, not percent-decoded" in CAP-03.
2. **CAP-02 method case.** No AC names a lowercase or mixed-case method. ConnTest upcases methods, so the property is only observable over real HTTP. It is now pinned by `test/whiq_web/capture_server_test.exs:65`. Recommend adding "including case" to CAP-02.
3. **CAP-12 duplicate `content-type`.** The spec does not say which value wins when the header is repeated. The implementation takes the first pair (`List.keyfind`, `lib/whiq/inspector.ex:69`), as design.md says. This is untested and unpinned by the spec. Minor.

---

## Fix Plans

Both fix plans from iteration 0 are done in `25e8342`:
- **Fix 1** (CAP-14/CAP-20, M10): non-loopback peer `{198, 51, 100, 9}` asserted as `"198.51.100.9"`. M10 killed.
- **Fix 2** (CAP-02, M15): raw `propfind` request over real Bandit, stored `"propfind"` asserted. M15 killed.

No open fix tasks.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| CAP-01 .. CAP-21 | Done (CAP-02, CAP-14, CAP-20 Needs Fix after iter 0) | Verified |

(The Verifier does not edit spec.md; the orchestrator applies this table.)

---

## Summary

**Overall**: Ready

**Spec-anchored check**: 21/21 ACs matched the spec outcome; 3 spec-precision gaps (non-blocking)
**Sensor**: 16/16 mutations killed (M10, M15 killed in iteration 1)
**Gate**: 70 passed, 0 failed, `mix precommit` exit 0

**What works**:
- Lookup by capture token, with expiry and the zero-query format guard.
- Byte-exact storage of the body and headers (including obs-text bytes), in received order.
- Method kept with its case, raw path and raw query.
- `body_size`/`content_type` derivation.
- Peer-address fallback and validated client-IP header.
- 404 for unknown, expired and view tokens, with nothing stored.
- Chunked de-chunking and 408 on read timeout over real Bandit.
- Prod `fly-client-ip` wiring.

**Issues found**: none open.

**Next steps**: the orchestrator may tighten the three spec-precision gaps in spec.md wording (optional), and should update the traceability statuses.
