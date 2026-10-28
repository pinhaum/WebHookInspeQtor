# Bin Creation Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/bin-creation/design.md`
**Status**: Approved

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec - confirm before Execute. Guidelines found: `AGENTS.md` (LiveView tests through `Phoenix.LiveViewTest` + `LazyHTML`, assert on element IDs, never raw HTML; `mix precommit` at the end). Floor: `test/whiq_web/controllers/capture_controller_test.exs` (one test per AC). Baseline suite: 12 tests.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Context (`Whiq.Inspector`) | integration (`Whiq.DataCase`, real Postgres) | 1:1 to the BIN ACs it owns (BIN-02, 03, 08, 09, 10, 12), every branch of the lookup | `test/whiq/**/*_test.exs` | `docker compose run --rm app mix test test/whiq` |
| Controller / router | integration (`Phoenix.ConnTest`) | Every route added: happy path + error path | `test/whiq_web/controllers/*_test.exs` | `docker compose run --rm app mix test` |
| LiveView | integration (`Phoenix.LiveViewTest`) | One test per BIN AC rendered by the page (BIN-04..07, 11) + every 404 path at HTTP level (BIN-08..10, 12) | `test/whiq_web/live/*_test.exs` | `docker compose run --rm app mix test` |
| Schema / migration | none | - (build gate; behavior is covered by the context tests) | - | build gate only |
| JS (`assets/js/app.js` clipboard listener) | none (no browser harness) | Wiring is asserted in the LiveView test; the clipboard write goes into the manual UAT checklist | - | build gate + manual UAT |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | Context-only tasks | `docker compose run --rm app mix test test/whiq` |
| Full | Tasks with ConnTest/LiveView tests | `docker compose run --rm app mix test` |
| Build | Last task of a phase, schema-only tasks | `docker compose run --rm app mix precommit` |

---

## Execution Plan

Phases run sequentially; tasks run in order within a phase.

### Phase 1: Domain

```
T1 → T2 → T3
```

### Phase 2: Bin page

```
T4 → T5 → T6
```

### Phase 3: Creation flow

```
T7 → T8
```

---

## Task Breakdown

### T1: Create the bins table and the Bin schema

**What**: Migration (via `mix ecto.gen.migration create_bins`) with `capture_token`, `view_token`, `expires_at` (`utc_datetime`, all `null: false`), `inserted_at` only, and unique indexes on both tokens; `Whiq.Inspector.Bin` schema matching it, with no cast changeset.
**Where**: `priv/repo/migrations/*_create_bins.exs` (new), `lib/whiq/inspector/bin.ex` (new)
**Depends on**: None
**Reuses**: design.md Data Models
**Requirement**: BIN-02, BIN-03 (storage only)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] `docker compose run --rm app mix ecto.migrate` and `mix ecto.rollback` both succeed
- [x] Gate check passes: `docker compose run --rm app mix precommit`
- [x] Test count: 12 tests pass (baseline, none skipped)

**Tests**: none
**Gate**: build

**Status**: ✅ Complete

**Commit**: `feat(inspector): add bins table and schema`

---

### T2: Implement Inspector.create_bin/0

**What**: Generates `capture_token` and `view_token` (`:crypto.strong_rand_bytes(24)` → url-safe base64 without padding), sets `inserted_at` to now truncated to the second and `expires_at` to exactly 7 days later, inserts and returns `{:ok, bin}`.
**Where**: `lib/whiq/inspector.ex` (new)
**Depends on**: T1
**Reuses**: `Whiq.Repo`
**Requirement**: BIN-02, BIN-03

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [x] `test/whiq/inspector_test.exs` asserts, against the persisted row (`Repo.get!`):
  - BIN-02: both tokens match `~r/\A[A-Za-z0-9_-]{32}\z/` and differ from each other; two bins never share a token
  - BIN-03: `DateTime.diff(expires_at, inserted_at) == 7 * 86_400`
- [x] Gate check passes: `docker compose run --rm app mix test test/whiq`
- [x] Test count: 12 + 2 tests pass

**Tests**: integration
**Gate**: quick

**Status**: ✅ Complete

**Commit**: `feat(inspector): create bins with capture and view tokens`

---

### T3: Implement Inspector.fetch_live_bin_by_view_token/1

**What**: Returns `{:error, :not_found}` without touching the Repo when the token fails `~r/\A[A-Za-z0-9_-]{32}\z/`; otherwise queries `view_token == ^token and expires_at > ^now` and returns `{:ok, bin}` or `{:error, :not_found}`.
**Where**: `lib/whiq/inspector.ex` (modify)
**Depends on**: T2
**Reuses**: `create_bin/0` for fixtures
**Requirement**: BIN-08, BIN-09, BIN-10, BIN-12

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [ ] `test/whiq/inspector_test.exs` has one test per case:
  - valid view token of a live bin → `{:ok, %Bin{id: ^id}}`
  - BIN-08: well-formed unknown token → `{:error, :not_found}`
  - BIN-09: the bin's `capture_token` → `{:error, :not_found}`
  - BIN-10: a bin whose `expires_at` was moved to the past (`Repo.update_all`) → `{:error, :not_found}`
  - BIN-12: tokens with `.`, `/`, `+`, `=` and wrong length → `{:error, :not_found}`, with a `:telemetry` handler on `[:whiq, :repo, :query]` receiving zero events
- [ ] Gate check passes: `docker compose run --rm app mix precommit`
- [ ] Test count: 14 + 5 tests pass

**Tests**: integration
**Gate**: build

**Commit**: `feat(inspector): look up live bins by view token`

---

### T4: Add the bin page route with 404 for every non-live token

**What**: `live "/bins/:token", BinLive` in the browser scope, `WhiqWeb.BinLive.mount/3` that loads the bin through the context and raises `WhiqWeb.BinNotFoundError` (`plug_status: 404`, own file) on `:not_found`, plus a minimal `Layouts.app` render with a `#bin-page` container.
**Where**: `lib/whiq_web/live/bin_live.ex` (new), `lib/whiq_web/bin_not_found_error.ex` (new), `lib/whiq_web/router.ex` (modify)
**Depends on**: None
**Reuses**: `Whiq.Inspector.fetch_live_bin_by_view_token/1`, `Layouts.app`, `ErrorHTML`
**Requirement**: BIN-08, BIN-09, BIN-10, BIN-12

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [ ] `test/whiq_web/live/bin_live_test.exs`:
  - live bin's view token → `live/2` mounts and `has_element?(view, "#bin-page")`
  - BIN-08, BIN-09, BIN-10, BIN-12: `assert_error_sent 404` for unknown, capture, expired and malformed tokens
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: 19 + 5 tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(bins): serve bin page only for live view tokens`

---

### T5: Render capture URL, expiry and save notice on the bin page

**What**: Assign only `capture_url` (`url(~p"/h/#{capture_token}")`, or the endpoint-URL fallback from design.md if verified routes warn) and `expires_at`; render `#capture-url` (readonly input), `#expires-at` (ISO 8601 UTC) and `#save-url-notice`.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify)
**Depends on**: T4
**Reuses**: `<.icon>`, `Layouts.app`
**Requirement**: BIN-04, BIN-05, BIN-06, BIN-11

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [ ] `test/whiq_web/live/bin_live_test.exs`:
  - BIN-04: `#capture-url` value equals `WhiqWeb.Endpoint.url() <> "/h/" <> capture_token`
  - BIN-05: `#expires-at` text equals `DateTime.to_iso8601(bin.expires_at)`
  - BIN-06: `#save-url-notice` text equals "Save this page's URL: it is the only way back to this bin."
  - BIN-11: neither the dead render (`html_response`) nor the connected render (`render(view)`) contains `view_token` (deliberate raw-HTML refute, design.md Risks)
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: 24 + 4 tests pass

**Tests**: integration
**Gate**: full

**Commit**: `feat(bins): show capture url, expiry and save notice`

---

### T6: Copy the capture URL to the clipboard

**What**: `#copy-capture-url` button with `phx-click={JS.dispatch("whiq:copy", to: "#capture-url")}` and a `whiq:copy` listener in `app.js` calling `navigator.clipboard.writeText(e.target.value)`, swallowing rejection.
**Where**: `lib/whiq_web/live/bin_live.ex` (modify), `assets/js/app.js` (modify)
**Depends on**: T5
**Reuses**: existing `window.addEventListener` block in `app.js`
**Requirement**: BIN-07

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `test/whiq_web/live/bin_live_test.exs`: the `#copy-capture-url` element's `phx-click` decodes to a `dispatch` of `whiq:copy` targeting `#capture-url`
- [ ] Manual UAT item recorded for the Verifier: in a browser on `http://localhost:4000`, Copy puts the capture URL on the clipboard
- [ ] Gate check passes: `docker compose run --rm app mix precommit`
- [ ] Test count: 28 + 1 tests pass

**Tests**: integration
**Gate**: build

**Commit**: `feat(bins): copy capture url to clipboard`

---

### T7: Create a bin from the home page

**What**: `post "/bins", BinController, :create` that calls `Inspector.create_bin/0` and redirects to `~p"/bins/#{view_token}"`; home template replaced by the product hero with `#create-bin-form` (`<.form>` POST, CSRF) and a "Create bin" button.
**Where**: `lib/whiq_web/controllers/bin_controller.ex` (new), `lib/whiq_web/controllers/page_html/home.html.heex` (modify), `lib/whiq_web/router.ex` (modify)
**Depends on**: None
**Reuses**: `:browser` pipeline, `<.button>`, `Layouts.app`
**Requirement**: BIN-01

**Tools**:

- MCP: NONE
- Skill: `frontend-design:frontend-design`

**Done when**:

- [ ] `test/whiq_web/controllers/bin_controller_test.exs`: BIN-01 `post ~p"/bins"` persists exactly one bin and `redirected_to(conn) == ~p"/bins/#{bin.view_token}"`; following the redirect mounts `#bin-page`
- [ ] `test/whiq_web/controllers/page_controller_test.exs`: the boilerplate text assertion is replaced by `#create-bin-form` with action `/bins` and method post (asserted via `LazyHTML`)
- [ ] Gate check passes: `docker compose run --rm app mix test`
- [ ] Test count: 29 + 1 tests pass (the page test is replaced, not added)

**Tests**: integration
**Gate**: full

**Commit**: `feat(bins): create a bin from the home page`

---

### T8: Replace the generator header with the whiq brand

**What**: `Layouts.app` header shows a `#site-brand` link to `/` with the whiq name and keeps the theme toggle; the Phoenix version badge and external Phoenix/GitHub links are removed.
**Where**: `lib/whiq_web/components/layouts.ex` (modify)
**Depends on**: T7
**Reuses**: `<.theme_toggle>`
**Requirement**: design.md Risks (layout boilerplate); supports BIN-01's home page

**Tools**:

- MCP: NONE
- Skill: `frontend-design:frontend-design`

**Done when**:

- [ ] `test/whiq_web/controllers/page_controller_test.exs`: `#site-brand` links to `/`, and no `a[href*="phoenixframework.org"]` remains
- [ ] Gate check passes: `docker compose run --rm app mix precommit`
- [ ] Test count: 30 + 1 tests pass

**Tests**: integration
**Gate**: build

**Commit**: `feat(layout): brand the app header as whiq`

---

## Phase Execution Map

```
Phase 1 → Phase 2 → Phase 3

Phase 1:  T1 ------→ T2 ------→ T3
Phase 2:  T4 ------→ T5 ------→ T6
Phase 3:  T7 ------→ T8
```

Each phase depends on the previous one as a whole: T4 needs the context from Phase 1, and T7 redirects to the page from Phase 2. That is why T4 and T7 have no intra-phase dependency.

---

## Validation

### Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: Migration + schema | One table and the struct that maps it | ⚠️ Cohesive, kept together |
| T2: `create_bin/0` | 1 function | ✅ Granular |
| T3: `fetch_live_bin_by_view_token/1` | 1 function | ✅ Granular |
| T4: Bin route + 404 | 1 route; the exception is only the 404 mechanism of this mount | ⚠️ Cohesive, kept together |
| T5: Bin page content | 1 LiveView render | ✅ Granular |
| T6: Copy | 1 button plus its listener; useless apart | ⚠️ Cohesive, kept together |
| T7: Create flow | 1 endpoint plus the form that posts to it | ⚠️ Cohesive, kept together |
| T8: Header brand | 1 component | ✅ Granular |

### Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | None | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T2 | T2 → T3 | ✅ Match |
| T4 | None (Phase 1) | None | ✅ Match |
| T5 | T4 | T4 → T5 | ✅ Match |
| T6 | T5 | T5 → T6 | ✅ Match |
| T7 | None (Phases 1-2) | None | ✅ Match |
| T8 | T7 | T7 → T8 | ✅ Match |

### Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Schema / migration | none | none | ✅ OK |
| T2 | Context | integration | integration | ✅ OK |
| T3 | Context | integration | integration | ✅ OK |
| T4 | Router + LiveView | integration | integration | ✅ OK |
| T5 | LiveView | integration | integration | ✅ OK |
| T6 | LiveView + JS | integration (highest) | integration | ✅ OK |
| T7 | Router + controller + template | integration | integration | ✅ OK |
| T8 | Layout component | integration (rendered through ConnTest) | integration | ✅ OK |
