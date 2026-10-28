# Live Inspection Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/live-inspection/design.md`
**Status**: Approved

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec - confirm before Execute. Guidelines found: `AGENTS.md` (LiveView tests via `Phoenix.LiveViewTest` + `LazyHTML`, assert on element ids, no `Process.sleep/1`, `mix precommit` at the end). Floor: `test/whiq/inspector_test.exs` (one test per AC, row read back) and `test/whiq_web/live/bin_live_test.exs` (`LazyHTML` queries by id). Baseline suite: 70 tests.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Pure formatting (`WhiqWeb.ByteFormat`) | unit (`ExUnit.Case, async: true`) | Every branch of `body/1`, `hex_dump/1`, `printable/1`; exact expected strings, including line breaks at 16 bytes, offsets past `0x0f`, and invalid UTF-8 after the first byte (LIVE-15) | `test/whiq_web/byte_format_test.exs` | `docker compose run --rm app mix test test/whiq_web/byte_format_test.exs` |
| Context (`Whiq.Inspector`) | integration (`Whiq.DataCase`, real Postgres) | Ordering, bin scoping and broadcast scoping: newest first with ties, another bin's rows excluded, foreign id → `:not_found`, broadcast received only on the capturing bin's topic | `test/whiq/inspector_test.exs` | `docker compose run --rm app mix test test/whiq/inspector_test.exs` |
| LiveView (`WhiqWeb.BinLive`) | integration (`Phoenix.LiveViewTest`) | 1:1 to LIVE-01..03, 05..09, 11..13, 15 through the real page: capture through `Inspector.capture_request/2`, assert by element id; hostile fixture with `<script>` and `0xff` bytes | `test/whiq_web/live/bin_live_test.exs` | `docker compose run --rm app mix test test/whiq_web/live/bin_live_test.exs` |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | Unit or context-only tasks | `docker compose run --rm app mix test <task test file>` |
| Full | LiveView tasks | `docker compose run --rm app mix test` |
| Build | Last task of a phase | `docker compose run --rm app mix precommit` |

---

## Execution Plan

Phases run sequentially; tasks run in order within a phase.

### Phase 1: Domain and formatting

```
T1 → T2 → T3
```

### Phase 2: Bin page

```
T4 → T5 → T6 → T7
```

---

## Task Breakdown

### T1: Implement WhiqWeb.ByteFormat

**What**: `body/1`, `hex_dump/1` and `printable/1` exactly as specified in design.md `WhiqWeb.ByteFormat`.
**Where**: `lib/whiq_web/byte_format.ex` (new)
**Depends on**: None
**Reuses**: `String.valid?/1`, `String.chunk/2`, `Base.encode16/2`
**Requirement**: LIVE-07, LIVE-08, LIVE-09, LIVE-15

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `body("")` → `:empty`; valid UTF-8 → `{:text, body}`; `"a" <> <<0xff>>` → `{:hex, ...}` of all bytes
- [ ] `hex_dump/1` of 17 bytes gives two lines, second offset `00000010`, lowercase hex
- [ ] `printable/1` escapes each invalid byte as `\xNN`, keeps valid runs, maps `nil` to `""`
- [ ] Gate check passes: `docker compose run --rm app mix test test/whiq_web/byte_format_test.exs`
- [ ] Test count: 70 + new tests pass

**Tests**: unit
**Gate**: quick

**Commit**: `feat(inspector): format captured bytes for display`

---

### T2: Implement Inspector.list_requests/1 and fetch_request/2

**What**: Summary list ordered `inserted_at desc, id desc` and a bin-scoped full fetch, per design.md.
**Where**: `lib/whiq/inspector.ex` (modify)
**Depends on**: T1
**Reuses**: `Ecto.Query` usage in `fetch_live_bin/2`
**Requirement**: LIVE-01, LIVE-06 (reads)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] List returns only the bin's rows, newest first, with `body` and `headers` not loaded
- [ ] `fetch_request/2` returns the full row for the bin and `{:error, :not_found}` for another bin's id
- [ ] Gate check passes: `docker compose run --rm app mix test test/whiq/inspector_test.exs`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: quick

**Commit**: `feat(inspector): list and fetch a bin's captured requests`

---

### T3: Broadcast captures on the bin's topic

**What**: `Inspector.subscribe/1` and a `{:request_captured, request}` broadcast after a successful insert in `capture_request/2`.
**Where**: `lib/whiq/inspector.ex` (modify)
**Depends on**: T2
**Reuses**: `Whiq.PubSub` from `lib/whiq/application.ex:14`
**Requirement**: LIVE-02, LIVE-03

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] A subscriber of bin A receives the stored request (same id) after a capture into A
- [ ] A subscriber of bin A receives nothing after a capture into bin B
- [ ] Gate check passes: `docker compose run --rm app mix precommit`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: build

**Commit**: `feat(inspector): broadcast captured requests per bin`

---

### T4: List captured requests on the bin page

**What**: `BinLive` mount streams `list_requests/1` into `#requests` with method, path, ISO 8601 timestamp and body size per row, plus `#empty-state` with the `curl` command while `request_count == 0`.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify)
**Depends on**: None (Phase 1)
**Reuses**: existing mount, stream conventions from `AGENTS.md`
**Requirement**: LIVE-01, LIVE-05

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Two captured requests render newest first with all four fields
- [ ] Empty bin shows `#empty-state` containing `curl` and the capture URL; it disappears once a request exists
- [ ] BIN-04..12 tests still pass
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(bins): list captured requests on the bin page`

---

### T5: Show new captures live

**What**: Subscribe on connected mount and `handle_info({:request_captured, request}, ...)` inserting at the top and incrementing `request_count`.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify)
**Depends on**: T4
**Reuses**: `Inspector.subscribe/1`
**Requirement**: LIVE-02, LIVE-03

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] A capture after mount appears as the first row of every open view of the bin (two views tested)
- [ ] A capture into another bin leaves the rendered page unchanged
- [ ] The empty state disappears on the first live arrival
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(bins): show captured requests live`

---

### T6: Show the selected request in detail

**What**: `#request-detail` for the newest request on load: method, path, raw query string, content type, remote IP, timestamp, body size, `#request-headers` in stored order, body as text, hex dump or "(empty body)", all through `ByteFormat` and HEEx escaping.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify)
**Depends on**: T5
**Reuses**: `WhiqWeb.ByteFormat`, `Inspector.fetch_request/2`
**Requirement**: LIVE-06, LIVE-07, LIVE-08, LIVE-09, LIVE-11, LIVE-12, LIVE-15

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Newest request is the one detailed on load
- [ ] Every field and header pair (including a repeated header name) renders in stored order
- [ ] `<script>` in a header, the query string and the body renders as text and adds no `script` element
- [ ] `0xff` in a header value and in the body renders (`\xff`, hex dump) without crashing the view
- [ ] Empty body shows "(empty body)"
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(bins): show the selected request in detail`

---

### T7: Select a request from the list

**What**: Each row is a control with `phx-click="select"` and its id; `handle_event("select", ...)` switches the detail and highlight; a live arrival selects only when nothing is selected.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify)
**Depends on**: T6
**Reuses**: `Inspector.fetch_request/2`
**Requirement**: LIVE-06, LIVE-13

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Clicking an older row shows its detail and marks it selected
- [ ] A live arrival while a request is selected keeps that selection
- [ ] A live arrival into an empty bin becomes the selection
- [ ] A forged `select` with another bin's id or a non-integer leaves the detail unchanged
- [ ] Gate check passes: `docker compose run --rm app mix precommit`
- [ ] Test count: previous + new tests pass

**Tests**: integration
**Gate**: build

**Commit**: `feat(bins): select a captured request from the list`

---

## Phase Execution Map

```
Phase 1 → Phase 2

Phase 1:  T1 ------→ T2 ------→ T3
Phase 2:  T4 ------→ T5 ------→ T6 ------→ T7
```

---

## Validation

### Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: ByteFormat | 1 module, 3 cohesive functions | ✅ Granular |
| T2: list/fetch | 2 read functions, same context | ✅ Granular |
| T3: subscribe/broadcast | 1 concern in the context | ✅ Granular |
| T4: list on page | mount + list markup | ✅ Granular |
| T5: live updates | 1 handle_info + subscribe | ✅ Granular |
| T6: detail pane | 1 template section | ✅ Granular |
| T7: selection | 1 handle_event + row control | ✅ Granular |

### Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | start of Phase 1 | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T2 | T2 → T3 | ✅ Match |
| T4 | None (Phase 1) | start of Phase 2 | ✅ Match |
| T5 | T4 | T4 → T5 | ✅ Match |
| T6 | T5 | T5 → T6 | ✅ Match |
| T7 | T6 | T6 → T7 | ✅ Match |

### Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Pure formatting | unit | unit | ✅ OK |
| T2 | Context | integration | integration | ✅ OK |
| T3 | Context | integration | integration | ✅ OK |
| T4 | LiveView | integration | integration | ✅ OK |
| T5 | LiveView | integration | integration | ✅ OK |
| T6 | LiveView | integration | integration | ✅ OK |
| T7 | LiveView | integration | integration | ✅ OK |
