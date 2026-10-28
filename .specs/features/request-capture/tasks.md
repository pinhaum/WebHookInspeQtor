# Request Capture Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/request-capture/design.md`
**Status**: Done

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec - confirm before Execute. Guidelines found: `AGENTS.md` (`start_supervised!/1` for processes in tests, no `Process.sleep/1`, `mix precommit` at the end). Floor: `test/whiq/inspector_test.exs` (one test per AC, `:telemetry` zero-query check) and `test/whiq_web/controllers/capture_controller_test.exs`. Baseline suite: 31 tests.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Context (`Whiq.Inspector`) | integration (`Whiq.DataCase`, real Postgres) | 1:1 to the CAP ACs it owns (CAP-06, 07, 11, 12, 15, 16, 17, 18, 21), every branch of the lookup, stored row read back with `Repo.get!` | `test/whiq/**/*_test.exs` | `docker compose run --rm app mix test test/whiq` |
| Web snapshot (`WhiqWeb.CaptureSnapshot`) | integration (`Plug.Test` conn, no DB) | One test per field rule: CAP-02..07, 13, 14, 20, 21 | `test/whiq_web/*_test.exs` | `docker compose run --rm app mix test test/whiq_web/capture_snapshot_test.exs` |
| Controller / router | integration (`Phoenix.ConnTest`) | Every AC end to end: happy path per method/content type + every 404 path (CAP-01..07, 09..12, 16..18) | `test/whiq_web/controllers/*_test.exs` | `docker compose run --rm app mix test` |
| Real HTTP server (Bandit over `:gen_tcp`) | integration (`async: false`) | The two ACs ConnTest cannot reach: CAP-08, CAP-19 | `test/whiq_web/capture_server_test.exs` | `docker compose run --rm app mix test` |
| Schema / migration / config | none | - (build gate; behavior is covered by the tests above) | - | build gate only |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | Context-only or snapshot-only tasks | `docker compose run --rm app mix test <task test file>` |
| Full | Tasks with ConnTest or real-server tests | `docker compose run --rm app mix test` |
| Build | Last task of a phase, schema/config-only tasks | `docker compose run --rm app mix precommit` |

---

## Execution Plan

Phases run sequentially; tasks run in order within a phase.

### Phase 1: Domain

```
T1 → T2 → T3
```

### Phase 2: Web capture

```
T4 → T5
```

### Phase 3: Transport fidelity and deploy config

```
T6 → T7
```

---

## Task Breakdown

### T1: Create the requests table and the CapturedRequest schema

**What**: Migration (via `mix ecto.gen.migration create_requests`) with the columns, nullability and `[:bin_id, :inserted_at]` index from design.md Data Models, FK `on_delete: :delete_all`; `Whiq.Inspector.CapturedRequest` schema on `requests` with no changeset; `has_many :requests` on `Bin`.
**Where**: `priv/repo/migrations/*_create_requests.exs` (new), `lib/whiq/inspector/captured_request.ex` (new), `lib/whiq/inspector/bin.ex` (modify)
**Depends on**: None
**Reuses**: `Bin` schema conventions, design.md Data Models
**Requirement**: CAP-01, CAP-06, CAP-07 (storage only)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] `docker compose run --rm app mix ecto.migrate` and `mix ecto.rollback` both succeed
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: 31 tests pass (baseline, none skipped)

**Tests**: none
**Gate**: build

**Status**: ✅ Complete

**Commit**: `feat(inspector): add requests table and schema`

---

### T2: Implement Inspector.fetch_live_bin_by_capture_token/1

**What**: Extract the body of `fetch_live_bin_by_view_token/1` into a private `fetch_live_bin/2` keyed by field, and add `fetch_live_bin_by_capture_token/1` on top of it.
**Where**: `lib/whiq/inspector.ex` (modify)
**Depends on**: T1
**Reuses**: `@token_format`, `create_bin/0` for fixtures, the `:telemetry` zero-query pattern in `test/whiq/inspector_test.exs`
**Requirement**: CAP-16, CAP-17, CAP-18

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [x] `test/whiq/inspector_test.exs`, `describe "fetch_live_bin_by_capture_token/1"`:
  - capture token of a live bin → `{:ok, %Bin{id: ^id}}`
  - CAP-16: well-formed unknown token → `{:error, :not_found}`
  - CAP-16: malformed token → `{:error, :not_found}` with zero `[:whiq, :repo, :query]` events
  - CAP-17: bin with `expires_at` moved to the past → `{:error, :not_found}`
  - CAP-18: the bin's `view_token` → `{:error, :not_found}`
- [x] Existing `fetch_live_bin_by_view_token/1` tests still pass unchanged
- [x] Gate check passes: `docker compose run --rm app mix test test/whiq`
- [x] Test count: 31 + 5 tests pass

**Tests**: integration
**Gate**: quick

**Status**: ✅ Complete

**Commit**: `feat(inspector): look up live bins by capture token`

---

### T3: Implement Inspector.capture_request/2

**What**: Pattern-matches `%{method, path, query_string, headers, body, remote_ip}` (a `%Plug.Conn{}` does not fit), derives `body_size = byte_size(body)` and `content_type` from the first `content-type` pair or nil, flattens `[{name, value}]` into `[n1, v1, ...]`, inserts with `inserted_at` as `utc_datetime_usec` and returns `{:ok, %CapturedRequest{}}`.
**Where**: `lib/whiq/inspector.ex` (modify)
**Depends on**: T2
**Reuses**: `create_bin/0` for fixtures
**Requirement**: CAP-06, CAP-07, CAP-11, CAP-12, CAP-15, CAP-21

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [x] `test/whiq/inspector_test.exs`, `describe "capture_request/2"`, each asserting against `Repo.get!(CapturedRequest, id)`:
  - every snapshot field is stored as given and `bin_id` is the bin's id
  - CAP-06: headers `[{"x-a", "1"}, {"x-b", "2"}, {"x-a", "3"}]` are stored as `["x-a", "1", "x-b", "2", "x-a", "3"]`
  - CAP-06 / AD-008: a header value containing `<<0xFF, 0x80>>` round-trips
  - CAP-07: a `:crypto.strong_rand_bytes(1024)` body round-trips byte-for-byte
  - CAP-11: `body_size == byte_size(body)` for a multibyte body (`"é"` → 2)
  - CAP-12: `content_type` equals the `content-type` header value; nil when the header is absent
  - CAP-15: passing a `%Plug.Conn{}` raises `FunctionClauseError` and stores nothing
  - CAP-21: empty body → `body == ""` and `body_size == 0`
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: 36 + 8 tests pass

**Tests**: integration
**Gate**: build

**Status**: ✅ Complete

**Commit**: `feat(inspector): store captured requests byte-for-byte`

---

### T4: Implement WhiqWeb.CaptureSnapshot.from_conn/1

**What**: Returns `{snapshot, conn}` per design.md: method as sent; path from `request_path` minus `"/h/<token>"`, still percent-encoded, `"/"` when empty; raw `query_string`; `req_headers` in order; body drained by a `read_body/2` loop with `read_timeout` from `:whiq, :capture_read_timeout` (default 15 000); `remote_ip` from the `:whiq, :client_ip_header` header when its value passes `:inet.parse_strict_address/1`, else `:inet.ntoa(conn.remote_ip)`.
**Where**: `lib/whiq_web/capture_snapshot.ex` (new)
**Depends on**: None (Phase 1)
**Reuses**: n/a
**Requirement**: CAP-02, CAP-03, CAP-04, CAP-05, CAP-06, CAP-07, CAP-13, CAP-14, CAP-20, CAP-21

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [x] `test/whiq_web/capture_snapshot_test.exs` (`async: false`, env restored in `on_exit`), conns built with `Plug.Test.conn/3`:
  - CAP-02: `"PROPFIND"` is kept
  - CAP-03: `/h/<token>/github/push` → `"/github/push"`; `/h/<token>/a%20b` → `"/a%20b"`
  - CAP-04: `/h/<token>` → `"/"`
  - CAP-05: `?b=2&a=%20` → `"b=2&a=%20"`
  - CAP-06: repeated headers keep their order
  - CAP-07: a body of 8 MB + 1 byte (above `read_body`'s default 8 000 000-byte `:length`, so it arrives in two reads) is returned complete
  - CAP-13: header configured with a valid IP value → that value
  - CAP-14: no header configured → the peer address (`"127.0.0.1"`)
  - CAP-20: header configured but absent → the peer address
  - CAP-20: header configured with `"not-an-ip"` → the peer address
  - CAP-21: no body → `""`
- [x] Gate check passes: `docker compose run --rm app mix test test/whiq_web/capture_snapshot_test.exs`
- [x] Test count: 44 + 11 tests pass

**Tests**: integration
**Gate**: quick

**Status**: ✅ Complete

**Commit**: `feat(capture): build plain snapshots from captured connections`

---

### T5: Capture requests in CaptureController

**What**: `capture/2` looks up the bin by `conn.path_params["token"]`; on `:not_found` answers `send_resp(404, "")` without reading the body; otherwise builds the snapshot, calls `Inspector.capture_request/2` and answers `send_resp(200, "")`.
**Where**: `lib/whiq_web/controllers/capture_controller.ex` (modify)
**Depends on**: T4
**Reuses**: `Inspector.fetch_live_bin_by_capture_token/1`, `Inspector.capture_request/2`, `CaptureSnapshot.from_conn/1`
**Requirement**: CAP-01, CAP-02, CAP-03, CAP-04, CAP-05, CAP-06, CAP-07, CAP-09, CAP-10, CAP-11, CAP-12, CAP-16, CAP-17, CAP-18

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [x] `test/whiq_web/controllers/capture_controller_test.exs` rewritten on real bins. The 6 `tok123` routing tests would now 404; each is replaced by the AC test that covers the same behavior, none is dropped. Each test asserts the single stored row:
  - CAP-01: one row for the bin, response 200 with `""` body
  - CAP-02: `HEAD`, `OPTIONS`, `PROPFIND`, and `POST` with `_method=DELETE` are stored with the method sent (4 tests)
  - CAP-03: `/github/push`; CAP-04: `/`
  - CAP-05: raw query string stored
  - CAP-06: repeated headers stored in order
  - CAP-07: random binary body stored byte-for-byte
  - CAP-09: multipart, urlencoded and JSON bodies stored as raw bytes (3 tests)
  - CAP-10: `:zlib.gzip/1` body with `content-encoding: gzip` → compressed bytes stored
  - CAP-11 + CAP-12: `body_size` and `content_type` match the request
  - CAP-16, CAP-17, CAP-18: unknown, expired and view token → 404 and zero rows (3 tests)
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: 55 − 6 + 18 = 67 tests pass (the list above sums to 18; the planned 19 was an arithmetic slip)

**Tests**: integration
**Gate**: build

**Status**: ✅ Complete

**Commit**: `feat(capture): store every request sent to a live bin`

---

### T6: Prove chunked bodies and read timeouts against a real Bandit server

**What**: Test module that starts `{Bandit, plug: WhiqWeb.Endpoint, ip: :loopback, port: 0}` with `start_supervised!`, reads the port from `ThousandIsland.listener_info/1`, uses the Ecto sandbox in shared mode and sends raw HTTP/1.1 over `:gen_tcp`; `config/test.exs` sets `:whiq, :capture_read_timeout` to 200.
**Where**: `test/whiq_web/capture_server_test.exs` (new), `config/test.exs` (modify)
**Depends on**: None (Phase 2)
**Reuses**: `Whiq.DataCase` sandbox setup, `Inspector.create_bin/0`
**Requirement**: CAP-08, CAP-19

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [x] `test/whiq_web/capture_server_test.exs` (`async: false`):
  - CAP-08: a `Transfer-Encoding: chunked` POST sent in three chunks → response 200 and the stored body equals the concatenated chunks
  - CAP-19: a POST declaring `content-length: 10` that sends 3 bytes and stalls → response status 408 and zero rows for the bin
- [x] Gate check passes: `docker compose run --rm app mix test`
- [x] Test count: 67 + 2 = 69 tests pass

**Tests**: integration
**Gate**: full

**Status**: ✅ Complete

**Commit**: `test(capture): cover chunked bodies and read timeouts over real http`

---

### T7: Read the client IP from fly-client-ip in production

**What**: Inside the `config_env() == :prod` block of `config/runtime.exs`, set `config :whiq, :client_ip_header, "fly-client-ip"`.
**Where**: `config/runtime.exs` (modify)
**Depends on**: T6
**Reuses**: existing prod block
**Requirement**: CAP-13 (deploy wiring; behavior tested in T4)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] The setting sits inside the prod block (prod boot needs secrets, so this is checked by reading the file)
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: 69 tests pass

**Tests**: none
**Gate**: build

**Status**: ✅ Complete

**Commit**: `feat(config): read client ip from fly-client-ip in production`

---

## Phase Execution Map

```
Phase 1 → Phase 2 → Phase 3

Phase 1:  T1 ------→ T2 ------→ T3
Phase 2:  T4 ------→ T5
Phase 3:  T6 ------→ T7
```

Each phase depends on the previous one as a whole: T4 has no domain dependency but sits after Phase 1 so T5 can wire both; T6 exercises the full capture path from Phase 2.

---

## Validation

### Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: Migration + schema + `has_many` | One table and the struct that maps it | ⚠️ Cohesive, kept together |
| T2: `fetch_live_bin_by_capture_token/1` | 1 function (plus the shared private helper) | ✅ Granular |
| T3: `capture_request/2` | 1 function | ✅ Granular |
| T4: `CaptureSnapshot.from_conn/1` | 1 module, 1 public function | ✅ Granular |
| T5: `CaptureController.capture/2` | 1 endpoint | ✅ Granular |
| T6: Real-server tests + test config | 1 test module and the config value it needs | ⚠️ Cohesive, kept together |
| T7: Prod client IP header | 1 config line | ✅ Granular |

### Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | None | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T2 | T2 → T3 | ✅ Match |
| T4 | None (Phase 1) | None | ✅ Match |
| T5 | T4 | T4 → T5 | ✅ Match |
| T6 | None (Phase 2) | None | ✅ Match |
| T7 | T6 | T6 → T7 | ✅ Match |

### Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Schema / migration | none | none | ✅ OK |
| T2 | Context | integration | integration | ✅ OK |
| T3 | Context | integration | integration | ✅ OK |
| T4 | Web snapshot | integration | integration | ✅ OK |
| T5 | Controller | integration | integration | ✅ OK |
| T6 | Real HTTP server tests + test config | integration (highest) | integration | ✅ OK |
| T7 | Config | none | none | ✅ OK |
