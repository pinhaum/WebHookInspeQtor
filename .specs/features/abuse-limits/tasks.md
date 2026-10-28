# Abuse Limits Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/abuse-limits/design.md`
**Status**: Approved

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec - confirm before Execute. Guidelines found: `AGENTS.md` (LiveView tests via `Phoenix.LiveViewTest` + `LazyHTML`, assert on element ids, `start_supervised!/1`, no `Process.sleep/1` for process sync, `mix precommit` at the end). Floor: `test/whiq/inspector_test.exs`, `test/whiq_web/controllers/capture_controller_test.exs`, `test/whiq_web/capture_server_test.exs`, `test/whiq_web/live/bin_live_test.exs`. Every limit gets a test that hits it and one just under it (spec Success Criteria).

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Migration / schema | none | build gate only | `priv/repo/migrations/` | `docker compose run --rm app mix precommit` |
| Rate limiter (`Whiq.RateLimit`) | unit (`ExUnit.Case`) | allow up to limit, deny above it with `retry_after` >= 1, keys independent, window reset (LIM-07) | `test/whiq/rate_limit_test.exs` | `docker compose run --rm app mix test test/whiq/rate_limit_test.exs` |
| Context (`Whiq.Inspector`) | integration (`Whiq.DataCase`, real Postgres) | 1:1 to LIM-01..05, LIM-11; exact byte counts at cap and cap+1; which id is evicted; broadcast payloads; LIM-04 with real parallel connections | `test/whiq/inspector_test.exs`, `test/whiq/inspector_concurrency_test.exs` | `docker compose run --rm app mix test test/whiq` |
| Controllers / snapshot (`/h`, `/bins`) | integration (`ConnTest`, real Bandit where ConnTest cannot reach) | LIM-01 over real HTTP, LIM-06, LIM-08, LIM-09, LIM-10, LIM-12; status, headers and stored rows | `test/whiq_web/controllers/*_test.exs`, `test/whiq_web/capture_server_test.exs`, `test/whiq_web/client_ip_test.exs` | `docker compose run --rm app mix test test/whiq_web` |
| LiveView (`WhiqWeb.BinLive`) | integration (`Phoenix.LiveViewTest`) | LIVE-04, LIVE-10, LIVE-14 by element id | `test/whiq_web/live/bin_live_test.exs` | `docker compose run --rm app mix test test/whiq_web/live/bin_live_test.exs` |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | Unit or single-file tasks | `docker compose run --rm app mix test <task test file>` |
| Full | Controller and LiveView tasks | `docker compose run --rm app mix test` |
| Build | Last task of a phase, migration/dependency tasks | `docker compose run --rm app mix precommit` |

---

## Execution Plan

Phases run sequentially; tasks run in order within a phase.

### Phase 1: Domain and limiter

```
T1 → T2 → T3 → T4
```

### Phase 2: Web layer

```
T5 → T6 → T7 → T8
```

### Phase 3: Bin page

```
T9 → T10
```

---

## Task Breakdown

### T1: Add the body_truncated column

**What**: Migration `add_body_truncated_to_requests` (`boolean`, `null: false`, `default: false`) via `mix ecto.gen.migration`, plus `field :body_truncated, :boolean, default: false` on `CapturedRequest`.
**Where**: `priv/repo/migrations/<ts>_add_body_truncated_to_requests.exs` (new)
**Depends on**: None
**Reuses**: `priv/repo/migrations/20261028172218_create_requests.exs` style
**Requirement**: LIM-01 (storage)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] Migration runs and rolls back
- [x] Schema field present
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: baseline passes unchanged

**Tests**: none
**Gate**: build

**Commit**: `feat(inspector): add body_truncated to captured requests`

---

### T2: Truncate oversized bodies on capture

**What**: `capture_request/2` stores at most `max_body_bytes` (config, 524,288) bytes, sets `body_truncated` when the snapshot body is longer, and derives `body_size` from the stored bytes.
**Where**: `lib/whiq/inspector.ex` (modify)
**Depends on**: T1
**Reuses**: existing `capture_request/2`
**Requirement**: LIM-01, LIM-02

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] 524,289-byte body → stored 524,288 bytes equal to the first 524,288 sent, `body_truncated` true, `body_size` 524,288
- [x] 524,288-byte body → stored whole, `body_truncated` false
- [x] `:max_body_bytes` added to `config/config.exs`
- [x] Gate check passes: `docker compose run --rm app mix test test/whiq/inspector_test.exs`
- [x] Test count: previous + new tests pass

**Tests**: integration
**Gate**: quick

**Commit**: `feat(inspector): truncate captured bodies over 512 KB`

---

### T3: Evict the oldest request past the cap

**What**: `capture_request/2` runs in a transaction that locks the bin row, inserts, deletes rows beyond `max_requests_per_bin` (100) ordered `inserted_at desc, id desc`, and after commit broadcasts `{:request_captured, r}` then `{:request_evicted, id}`; a missing bin returns `{:error, :not_found}`.
**Where**: `lib/whiq/inspector.ex` (modify)
**Depends on**: T2
**Reuses**: `topic/1`, `Phoenix.PubSub` broadcast
**Requirement**: LIM-03, LIM-04, LIM-05, LIM-11

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] Bin with 100 requests + 1 capture → 100 rows, the oldest id gone, the new id present
- [x] Bin with 99 requests + 1 capture → 100 rows, nothing evicted, no `:request_evicted` message
- [x] Subscriber receives `{:request_evicted, oldest_id}` after `{:request_captured, _}`
- [x] Truncated capture into a full bin → stored truncated and oldest evicted (LIM-11)
- [x] `test/whiq/inspector_concurrency_test.exs` (`async: false`, sandbox `:auto`, bin deleted in `on_exit`): 95 requests + 20 parallel captures → exactly 100 rows, the 100 newest ids; confirm the tasks use distinct connections (e.g. distinct `pg_backend_pid()`)
- [x] `:max_requests_per_bin` added to `config/config.exs`
- [x] Gate check passes: `docker compose run --rm app mix test test/whiq`
- [x] Test count: previous + new tests pass

**Tests**: integration
**Gate**: quick

**Commit**: `feat(inspector): keep the newest 100 requests per bin`

---

### T4: Add the Hammer rate limiter

**What**: `{:hammer, "~> 7.5"}` locked at 7.5.0, `Whiq.RateLimit` with `use Hammer, backend: :ets` and `check/3`, started in `Whiq.Application` before the endpoint.
**Where**: `lib/whiq/rate_limit.ex` (new)
**Depends on**: T3
**Reuses**: Hammer `hit/3`
**Requirement**: LIM-07

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] `mix.lock` pins hammer 7.5.0
- [x] `check/3` returns `:ok` for hits 1..limit and `{:error, s}` with `s >= 1` for hit limit+1
- [x] Two keys count independently
- [x] LIM-07: with `scale_ms: 1000`, after a deny, waiting the denied seconds makes the next `check/3` return `:ok`
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: previous + new tests pass

**Tests**: unit
**Gate**: build

**Commit**: `feat(limits): add fixed-window rate limiter`

---

### T5: Extract client IP resolution

**What**: Move `CaptureSnapshot.remote_ip/1` verbatim to `WhiqWeb.ClientIP.from_conn/1` and call it from the snapshot.
**Where**: `lib/whiq_web/client_ip.ex` (new)
**Depends on**: None (Phase 1)
**Reuses**: `lib/whiq_web/capture_snapshot.ex:47`
**Requirement**: LIM-10 (prerequisite)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] Unit tests: configured header with a valid IP wins; invalid header value or no header falls back to the peer address (input distinct from the ConnTest default, L-003)
- [x] CAP-14 and CAP-20 tests still pass
- [x] Gate check passes: `docker compose run --rm app mix test test/whiq_web`
- [x] Test count: previous + new tests pass

**Tests**: integration
**Gate**: quick

**Commit**: `refactor(web): extract client ip resolution`

---

### T6: Read capture bodies up to the cap

**What**: `CaptureSnapshot.from_conn/1` stops reading after `max_body_bytes + 1` bytes without draining the rest; the controller answers `{:error, :not_found}` from `capture_request/2` with 404.
**Where**: `lib/whiq_web/capture_snapshot.ex` (modify)
**Depends on**: T5
**Reuses**: `read_full_body/2`, `capture_server_test.exs` harness
**Requirement**: LIM-01, LIM-02

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] ConnTest: 524,289-byte POST → 200, row truncated; 524,288-byte POST → 200, row whole
- [x] Real server: a 1 MB `content-length` body → status line `200`, row stored with 524,288 bytes and `body_truncated` true
- [x] Gate check passes: `docker compose run --rm app mix test`
- [x] Test count: previous + new tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(capture): stop reading bodies past the size cap`

---

### T7: Rate-limit captures per bin

**What**: `CaptureController` checks `{:capture, bin.id}` against `:capture_rate_limit` after the bin lookup and before reading the body; deny → 429, `retry-after` seconds, nothing stored.
**Where**: `lib/whiq_web/controllers/capture_controller.ex` (modify)
**Depends on**: T6
**Reuses**: `Whiq.RateLimit.check/3`
**Requirement**: LIM-06, LIM-08, LIM-12

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] Config: prod/dev `limit: 60, scale_ms: 60_000`; test `limit: 2, scale_ms: 3_600_000`
- [x] Captures 1 and 2 → 200 (just under); capture 3 → 429 with an integer `retry-after` >= 1 and the bin still holds 2 rows
- [x] LIM-12: a full bin (100 rows) that gets 429 still holds the same 100 ids
- [x] LIM-08: while bin A is limited, a capture into bin B → 200
- [x] Gate check passes: `docker compose run --rm app mix test`
- [x] Test count: previous + new tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(capture): rate-limit captures per bin`

---

### T8: Rate-limit bin creation per client IP

**What**: `BinController.create` checks `{:bin, ClientIP.from_conn(conn)}` against `:bin_rate_limit`; deny → flash error "Too many bins created. Try again later." and redirect to `/`, no bin created.
**Where**: `lib/whiq_web/controllers/bin_controller.ex` (modify)
**Depends on**: T7
**Reuses**: `Whiq.RateLimit.check/3`, `WhiqWeb.ClientIP`, home page flash
**Requirement**: LIM-09, LIM-10

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] Config: prod/dev `limit: 10, scale_ms: 3_600_000`; test `limit: 1, scale_ms: 3_600_000`
- [x] Tests set a unique `remote_ip` per test; first POST from an IP → redirect to the bin (just under); second → redirect to `/`, flash shown on the home page, bin count unchanged
- [x] LIM-10: a second IP still creates a bin while the first is limited
- [x] BIN-01 still passes
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: previous + new tests pass

**Tests**: integration
**Gate**: build

**Commit**: `feat(bins): rate-limit bin creation per client ip`

---

### T9: Remove evicted requests from the bin page

**What**: `BinLive.handle_info({:request_evicted, id}, ...)` deletes `requests-<id>` from the stream, decrements `request_count`, and when it was selected selects the newest remaining request.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify)
**Depends on**: None (Phase 2)
**Reuses**: `newest/2`, `select/2`
**Requirement**: LIVE-04, LIVE-14

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Full bin + 1 capture → the oldest row disappears from every open page (two views), the new row is first
- [ ] Selected oldest request evicted → `#request-detail` shows the newest remaining request
- [ ] Unselected eviction keeps the current selection
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(bins): drop evicted requests from the page`

---

### T10: Show the truncation notice

**What**: `#body-truncated` in the detail pane reading "Body truncated: showing the first <body_size> bytes" when `body_truncated` is true.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify)
**Depends on**: T9
**Reuses**: detail pane markup
**Requirement**: LIVE-10

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Truncated request shows `#body-truncated` with the exact text and `524288`
- [ ] Untruncated request has no `#body-truncated`
- [ ] Gate check passes: `docker compose run --rm app mix precommit`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: build

**Commit**: `feat(bins): flag truncated bodies in the detail pane`

---

## Phase Execution Map

```
Phase 1 → Phase 2 → Phase 3

Phase 1:  T1 ------→ T2 ------→ T3 ------→ T4
Phase 2:  T5 ------→ T6 ------→ T7 ------→ T8
Phase 3:  T9 ------→ T10
```

---

## Validation

### Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: column | 1 migration + 1 schema field | ✅ Granular |
| T2: truncation | 1 rule in `capture_request/2` | ✅ Granular |
| T3: ring buffer | 1 transaction in `capture_request/2` | ✅ Granular |
| T4: limiter | 1 module + dep wiring | ✅ Granular |
| T5: ClientIP | 1 extracted function | ✅ Granular |
| T6: bounded read | 1 function | ✅ Granular |
| T7: capture limit | 1 controller action | ✅ Granular |
| T8: bin limit | 1 controller action | ✅ Granular |
| T9: eviction on page | 1 handle_info | ✅ Granular |
| T10: notice | 1 template element | ✅ Granular |

### Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | start of Phase 1 | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T2 | T2 → T3 | ✅ Match |
| T4 | T3 | T3 → T4 | ✅ Match |
| T5 | None (Phase 1) | start of Phase 2 | ✅ Match |
| T6 | T5 | T5 → T6 | ✅ Match |
| T7 | T6 | T6 → T7 | ✅ Match |
| T8 | T7 | T7 → T8 | ✅ Match |
| T9 | None (Phase 2) | start of Phase 3 | ✅ Match |
| T10 | T9 | T9 → T10 | ✅ Match |

### Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Migration / schema | none | none | ✅ OK |
| T2 | Context | integration | integration | ✅ OK |
| T3 | Context | integration | integration | ✅ OK |
| T4 | Rate limiter | unit | unit | ✅ OK |
| T5 | Controllers / snapshot | integration | integration | ✅ OK |
| T6 | Controllers / snapshot | integration | integration | ✅ OK |
| T7 | Controllers | integration | integration | ✅ OK |
| T8 | Controllers | integration | integration | ✅ OK |
| T9 | LiveView | integration | integration | ✅ OK |
| T10 | LiveView | integration | integration | ✅ OK |
