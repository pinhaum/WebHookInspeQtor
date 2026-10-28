# Bin Creation Validation

**Result**: PASS (after fix iteration 2 of 3; BIN-07 OS-clipboard paste remains a manual UAT item)

**Date**: 2026-10-28
**Spec**: `.specs/features/bin-creation/spec.md`
**Diff range**: `c62b084..da3c6e4` (8 implementation commits + fix commits `05d1903`, `da3c6e4` on `feat/bin-creation`)
**Verifier**: independent sub-agent (author != verifier)

---

## Re-verification log

| Iteration | Commit | Gap addressed | Outcome |
| --------- | ------ | ------------- | ------- |
| 0 | `cb1522f` | - | FAIL: M10 (button removed) survived |
| 1 | `05d1903` `test(bins): assert the create bin button on the home form` | Gap 1 / M10 | M10, M10b, M10c killed; M10d (`type="button"`) survives -> still FAIL |
| 2 | `da3c6e4` `test(bins): require the create bin button to submit the form` | Gap 2 / M10d | M10, M10b, M10c, M10d, M10e all killed -> PASS |

Judgment on iteration 2: `test/whiq_web/controllers/page_controller_test.exs:16` `Enum.count(button) == 1` and `:18` `LazyHTML.attribute(button, "type") in [[], ["submit"]]` close the gap; independently confirmed by re-running M10d and a new `type="reset"` variant (M10e), both killed. Accepting a missing `type` is correct (HTML default is submit) and matches what `<.button>` renders.

Judgment on iteration 1: the author is right that `<.button>` renders a bare `<button>` (`lib/whiq_web/components/core_components.ex:117-121`, `type` is not in the `:global` include list) and that a `<button>` without `type` in a form submits per HTML. That makes the current markup correct, but the test still does not pin the submit semantics: replacing the control with `<button type="button" ...>` (the exact pattern already used by `#copy-capture-url` in `bin_live.ex`) breaks BIN-01 and all tests pass. Adding `type` to the template is not required; the test only needs to refuse a non-submit type.

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | Done | migration + schema (`priv/repo/migrations/20261028130326_create_bins.exs`, `lib/whiq/inspector/bin.ex`) |
| T2 | Done | `lib/whiq/inspector.ex:19` `create_bin/0` |
| T3 | Done | `lib/whiq/inspector.ex:34` `fetch_live_bin_by_view_token/1` |
| T4 | Done | route `lib/whiq_web/router.ex:19`, `WhiqWeb.BinNotFoundError` (`plug_status: 404`) |
| T5 | Done | `lib/whiq_web/live/bin_live.ex` |
| T6 | Done (manual UAT pending) | button + `assets/js/app.js:43` listener |
| T7 | Done | presence, label (`05d1903`) and submit type (`da3c6e4`) asserted |
| T8 | Done | `#site-brand` header |

---

## Spec-Anchored Acceptance Criteria

| AC | Spec-defined outcome | `file:line` + assertion | Result |
| -- | -------------------- | ----------------------- | ------ |
| BIN-01 | Click "Create bin" on `/` persists a bin and navigates to `/bins/:view_token` | `test/whiq_web/controllers/bin_controller_test.exs:10` `assert [bin] = Repo.all(Bin)`; `:11` `redirected_to(conn) == ~p"/bins/#{bin.view_token}"`; `:14` follow redirect `has_element?(view, "#bin-page")`; `test/whiq_web/controllers/page_controller_test.exs:12-13` form `action == ["/bins"]`, `method == ["post"]`; `:16` exactly one `button#create-bin-button` inside the form, `:18` `type in [[], ["submit"]]`, `:19` trimmed text `== "Create bin"` | PASS (after fix iterations 1-2) |
| BIN-02 | Two different 32-char url-safe base64 tokens | `test/whiq/inspector_test.exs:17-19` both `=~ ~r/\A[A-Za-z0-9_-]{32}\z/`, `capture_token != view_token`; `:22` 4 tokens across 2 bins unique; read back via `Repo.get!` | PASS |
| BIN-03 | `expires_at` exactly 7 days after `inserted_at` | `test/whiq/inspector_test.exs:30` `DateTime.diff(bin.expires_at, bin.inserted_at) == 7 * 86_400` (persisted row) | PASS |
| BIN-04 | Absolute capture URL `<endpoint url>/h/<capture_token>` | `test/whiq_web/live/bin_live_test.exs:50-53` `#capture-url` `value == [WhiqWeb.Endpoint.url() <> "/h/" <> bin.capture_token]` | PASS |
| BIN-05 | Expiry as ISO 8601 UTC | `test/whiq_web/live/bin_live_test.exs:57-58` `#expires-at` text `== DateTime.to_iso8601(bin.expires_at)` (UTC `DateTime` -> `...Z`) | PASS |
| BIN-06 | Notice "Save this page's URL: it is the only way back to this bin." | `test/whiq_web/live/bin_live_test.exs:62-63` `#save-url-notice` text `==` exact string | PASS |
| BIN-07 | Copy writes the capture URL to the clipboard | `test/whiq_web/live/bin_live_test.exs:75-80` `phx-click` decodes to `[["dispatch", %{"event" => "whiq:copy", "to" => "#capture-url"}]]`; listener `assets/js/app.js:43` has no harness. Independent Verifier browser check (Chrome DevTools, dev server, fresh bin): clicking `#copy-capture-url` called `navigator.clipboard.writeText` exactly once with `http://localhost:4000/h/<capture_token>`, equal to `#capture-url` value | PASS (automated wiring + independent browser check); OS clipboard write = manual UAT pending |
| BIN-08 | Unknown token -> 404 | context `test/whiq/inspector_test.exs:44-45` `== {:error, :not_found}`; HTTP `test/whiq_web/live/bin_live_test.exs:24` `assert_error_sent 404` | PASS |
| BIN-09 | Capture token on `/bins/` -> 404 | `test/whiq/inspector_test.exs:51`; `test/whiq_web/live/bin_live_test.exs:28` `assert_error_sent 404` | PASS |
| BIN-10 | After `expires_at` -> 404 | `test/whiq/inspector_test.exs:56-59` (expires_at set 1 s in the past); `test/whiq_web/live/bin_live_test.exs:32-35` `assert_error_sent 404` | PASS |
| BIN-11 | View token never rendered | `test/whiq_web/live/bin_live_test.exs:68-71` `refute dead_html =~ bin.view_token`, `refute render(view) =~ bin.view_token`. Raw-HTML refute is the documented exception in `design.md` (Risks): the requirement is the absence of a string, which element selectors cannot express. Accepted. Browser check also confirmed `document.body.innerHTML` lacks the view token on the connected page | PASS |
| BIN-12 (edge) | Malformed token -> 404 without DB query | `test/whiq/inspector_test.exs:88-92` six malformed tokens (`.`, `/`, `+`, `=`, 31 and 33 chars) `== {:error, :not_found}` + `refute_received :repo_query` via `[:whiq, :repo, :query]` telemetry; HTTP `test/whiq_web/live/bin_live_test.exs:39` `assert_error_sent 404` | PASS |

Additional (unclaimed-by-AC but mapped to Done-when): live view token mounts (`test/whiq/inspector_test.exs:38`, `test/whiq_web/live/bin_live_test.exs:18-20`); header brand T8 (`test/whiq_web/controllers/page_controller_test.exs:19-21`).

**Status**: 12/12 ACs matched spec outcome with discriminating tests. No spec-precision gaps.

---

## Discrimination Sensor

Isolation: file copies in the scratchpad (`verifier/<id>.orig`), mutate in place (Docker bind mount), run tests, restore with `cp`. `git status --porcelain` baseline was empty and was empty after every restore.

| # | File:line | Mutation | Tests run | Result |
| - | --------- | -------- | --------- | ------ |
| M1 | `lib/whiq/inspector.ex:35` | Drop token-format guard (`if true do`) | inspector_test | Killed (1 failure: BIN-12 telemetry) |
| M2 | `lib/whiq/inspector.ex:39` | Drop `expires_at > ^now` | inspector_test + bin_live_test | Killed (2: BIN-10 context + HTTP) |
| M3 | `lib/whiq/inspector.ex:12` | TTL 7 -> 6 days | inspector_test | Killed (1: BIN-03) |
| M4 | `lib/whiq/inspector.ex:23-24` | Same token for capture and view | inspector_test | Killed (2: BIN-02, BIN-09) |
| M5 | `lib/whiq_web/live/bin_live.ex:13` | Capture URL built from `view_token` | bin_live_test | Killed (2: BIN-04, BIN-11) |
| M6 | `lib/whiq_web/live/bin_live.ex:14` | Append view token to rendered expiry | bin_live_test | Killed (2: BIN-05, BIN-11) |
| M7 | `lib/whiq_web/controllers/bin_controller.ex:8` | Redirect to `capture_token` | bin_controller_test | Killed (1: BIN-01) |
| M8 | `lib/whiq_web/live/bin_live.ex:41` | `JS.dispatch` target `#capture-url` -> `#copy-capture-url` | bin_live_test | Killed (1: BIN-07) |
| M9 | `lib/whiq/inspector.ex:39` | `expires_at > ^now` -> `>=` | inspector_test + bin_live_test | Survived - equivalent w.r.t. spec (BIN-10 only constrains requests *after* `expires_at`; both operators conform). Not a gap |
| M10 | `lib/whiq_web/controllers/page_html/home.html.heex:14` | Remove the "Create bin" button from `#create-bin-form` | page_controller_test + bin_controller_test | iter 0: Survived; iter 1-2: Killed (1) |
| M10b | `lib/whiq_web/controllers/page_html/home.html.heex:14` | Move the button outside `#create-bin-form` | page_controller_test | iter 1-2: Killed (1) |
| M10c | `lib/whiq_web/controllers/page_html/home.html.heex:15` | Label "Create bin" -> "Create" | page_controller_test | iter 1-2: Killed (1) |
| M10d | `lib/whiq_web/controllers/page_html/home.html.heex:14` | Replace `<.button>` with raw `<button type="button" id="create-bin-button">` (no longer submits) | page_controller_test | iter 1: Survived; iter 2 (`da3c6e4`): Killed (1) |
| M10e | `lib/whiq_web/controllers/page_html/home.html.heex:14` | Raw `<button type="reset" id="create-bin-button">` | page_controller_test | iter 2: Killed (1) |
| M11 | `lib/whiq_web/controllers/page_html/home.html.heex:13` | Form `method="post"` -> `"get"` | page_controller_test | Killed (1) |
| M12 | `assets/js/app.js:43` | `writeText(e.target.value)` -> `writeText(e.target.id)` | full suite | Survived - expected: JS layer has no harness by design (tasks.md Test Coverage Matrix: "none, manual UAT"). Routed to UAT, not counted as a test gap |

**Sensor depth**: lightweight+ (16 mutations across all iterations; feature is access-control relevant, so token/expiry branches were all exercised)
**Sensor result** (iteration 2): 14/14 discriminating mutants killed; M9 equivalent, M12 out-of-harness by design (UAT); 0 real survivors

---

## Interactive UAT

| # | Test | Result | Details |
| - | ---- | ------ | ------- |
| 1 | BIN-07: open a bin on `http://localhost:4000`, click Copy, paste elsewhere: clipboard holds the capture URL | Pending (human) | Verifier cannot reach the OS clipboard. Independent browser check confirmed the page calls `navigator.clipboard.writeText(<capture url>)`; the remaining risk is only the browser/OS honoring the call (secure context: localhost qualifies) |

Judgment: BIN-07 is not counted as a gap. The system's observable contract ends at calling the Clipboard API with the right value, which is verified twice (LiveView wiring test + independent browser check). The human paste check stays as a UAT item for the orchestrator to run with the user; a failure there would reopen BIN-07.

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | OK - context is 2 public functions, controller 1 action |
| Surgical changes | OK - only files listed in tasks.md touched |
| No scope creep | OK |
| Matches patterns | OK - context boundary respected (web layer never calls `Repo` for bins), `plug_status` exception, no cast changeset per AGENTS.md |
| Spec-anchored outcome check | OK |
| Per-layer coverage (context 1:1; routes happy+error) | OK - `/bins/:token` happy + 4 error paths, `POST /bins` happy path (no error path exists) |
| Every test maps to a requirement | OK |
| Guidelines followed: `AGENTS.md` | Mostly. Advisory (non-blocking): `bin_live.ex` and `home.html.heex` use daisyUI classes (`btn`, `join`, `input`, `alert`) although AGENTS.md asks for hand-written Tailwind components; the generator layout already does the same, so this follows existing project style. BIN-11 raw-HTML refute is a documented exception |

---

## Edge Cases

- [x] BIN-12 malformed token -> 404 with zero repo queries (telemetry-proved; M1 killed)
- [x] Token collision: no retry, unique indexes on both columns (migration) - by design, untested (negligible probability, spec-accepted)

---

## Gate Check

- **Gate command**: `docker compose run --rm app mix precommit` (exit 0 at `cb1522f`, `05d1903` and `da3c6e4`; 31 tests, 0 failures)
- **Full suite**: `docker compose run --rm app mix test` -> 31 tests, 0 failures, 0 skipped
- **Test count before feature**: 12 (tasks.md baseline)
- **Test count after feature**: 31
- **Delta**: +19 (one boilerplate page test replaced, as planned in T7)
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans

### Fix 1: Assert the "Create bin" trigger on the home page (BIN-01) - done in `05d1903`, M10 killed

- **Root cause**: `page_controller_test.exs` checks only the form's `action`/`method`; nothing asserts the form contains a submit control, so the user-facing trigger of BIN-01 can disappear unnoticed (M10).
- **Fix task**: in `test/whiq_web/controllers/page_controller_test.exs`, assert `#create-bin-form #create-bin-button` exists, is a submit button (`type="submit"` or default), and its trimmed text is `"Create bin"`.
- **Verify**: re-run M10 (remove the button) -> test fails.
- **Priority**: Minor (test-only; behavior is correct today)

### Fix 2: Pin that `#create-bin-button` submits the form (BIN-01, iteration 1) - done in `da3c6e4`, M10d killed

- **Root cause**: the iteration-1 test checks presence and label but not that the control is a submit button, so `type="button"` survives (M10d).
- **Fix task**: in `test/whiq_web/controllers/page_controller_test.exs`, select the button with a selector that excludes non-submit types, e.g. `LazyHTML.query(form, ~s(button#create-bin-button:not([type="button"]):not([type="reset"])))`, and assert exactly one match (keep the label assertion). No template change needed. Not verified by the Verifier: whether LazyHTML supports `:not()` with attribute selectors; if not, assert `LazyHTML.attribute(button, "type")` is not `["button"]`/`["reset"]` instead.
- **Verify**: re-run M10d -> test fails; M10, M10b, M10c stay killed.
- **Priority**: Minor (test-only)

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| BIN-01 | Done | Verified (after fix iterations 1-2) |
| BIN-02..06 | Done | Verified |
| BIN-07 | Done (UAT pending) | Verified (automated); UAT pending |
| BIN-08..12 | Done | Verified |

---

## Summary

**Overall**: Ready (pending only the BIN-07 human paste check).

**Spec-anchored check**: 12/12 ACs matched spec outcome; 0 spec-precision gaps
**Sensor**: 14/14 discriminating mutants killed (+1 equivalent, +1 out-of-harness by design)
**Gate**: 31 passed, 0 failed; `mix precommit` clean

**What works**: token generation and format, 7-day TTL, view-token-only access with uniform 404 for unknown/capture/expired/malformed tokens (no DB hit for malformed), capture URL/expiry/notice rendering, view token never rendered, Copy wiring to the Clipboard API.

**Issues found**: BIN-01 trigger coverage gaps, both fixed (Fix 1 `05d1903`, Fix 2 `da3c6e4`). None open.

**Next steps**: run the BIN-07 human paste check with the user.
