# Live Inspection Validation

**Result**: PASS (iteration 0: 12/12 ACs discriminated on the spec outcome, build gate green with 104 tests, 26/26 mutants killed, 0 spec-precision gaps)

**Date**: 2026-10-28
**Spec**: `.specs/features/live-inspection/spec.md`
**Diff range**: `43f6d64..bb0f285` (T1 `afabcd8`, T2 `b9b4155`, T3 `e6d0196`, T4 `5cf7eaa`, T5 `581eb5b`, T6 `5a0eeb7`, T7 `bb0f285` on `feat/live-inspection`)
**Verifier**: independent sub-agent (author != verifier)

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | Done | `lib/whiq_web/byte_format.ex:12` `body/1`, `:22` `hex_dump/1`, `:39` `printable/1` |
| T2 | Done | `lib/whiq/inspector.ex:91` `list_requests/1` (summary fields only, `desc: inserted_at, desc: id`), `:102` `fetch_request/2` scoped by `bin_id` |
| T3 | Done | `lib/whiq/inspector.ex:76` broadcast after a successful insert, `:84` `subscribe/1`, `:125` topic `"bin:#{id}"` |
| T4 | Done | `lib/whiq_web/live/bin_live.ex:10-27` mount lists requests into a stream; `:122-128` empty state on `@request_count == 0` |
| T5 | Done | `lib/whiq_web/live/bin_live.ex:15` subscribe when connected; `:45-53` `handle_info` inserts `at: 0` and bumps the count |
| T6 | Done | `lib/whiq_web/live/bin_live.ex:154-220` detail pane; every captured byte goes through HEEx escaping, `ByteFormat.printable/1` or `ByteFormat.body/1`; no `raw/1` in the module |
| T7 | Done | `lib/whiq_web/live/bin_live.ex:58-76` `select` event (strict `Integer.parse` + bin-scoped fetch), highlight moved by re-inserting both rows |

All `Done when` boxes in `tasks.md` are checked. No test was deleted in the diff range (`git diff 43f6d64..bb0f285 -- test` has no removed `test "` line).

---

## Spec-Anchored Acceptance Criteria

Payload/conjunction rule: LiveView assertions read the rendered value by element id (`LazyHTML` text or attribute) and compare it to an exact expected string. Context assertions compare ids, whole structs or `{:error, :not_found}`.

| AC | Spec-defined outcome | `file:line` + assertion | Result |
| -- | -------------------- | ----------------------- | ------ |
| LIVE-01 | Bin's requests newest first, each with method, path, timestamp, body size (timestamp format and `N bytes` pinned in `design.md:91`) | `test/whiq_web/live/bin_live_test.exs:119` `row_ids(document) == ["requests-#{newer.id}", "requests-#{older.id}"]`; `:121-135` method `== "DELETE"`/`"PUT"`, path `== "/newer"`/`"/older"`, time `== DateTime.to_iso8601(...)`, size `== "0 bytes"`/`"3 bytes"`; context `test/whiq/inspector_test.exs:282` other bin excluded, `:294` same-timestamp tie broken by id desc, `:302-308` summary fields only | PASS |
| LIVE-02 | Every open page of the bin shows the new capture at the top, without reload | `test/whiq_web/live/bin_live_test.exs:169-173` for two views: `row_ids(document) == ["requests-#{newer.id}", "requests-#{older.id}"]`, path `== "/live"`; context `test/whiq/inspector_test.exs:259-260` `assert_received {:request_captured, request}`, `request == Repo.get!(...)` | PASS |
| LIVE-03 | A capture into another bin leaves the page unchanged | `test/whiq_web/live/bin_live_test.exs:185` `render(view) == before`; context `test/whiq/inspector_test.exs:270` `refute_received {:request_captured, _}` | PASS |
| LIVE-05 | Empty bin shows an empty state with a `curl` to the capture URL (exact command pinned in `design.md:91`) | `test/whiq_web/live/bin_live_test.exs:144` `text(document, "#empty-state-curl") == "curl -d 'hello' #{capture_url}"`; `:154` hidden when a request exists; `:191`/`:195` disappears on first live arrival | PASS |
| LIVE-06 | Selecting a request shows method, path, raw query, content type, remote IP, timestamp, body size and every header pair in stored order | Trigger control (L-001/L-002): `test/whiq_web/live/bin_live_test.exs:356-359` `button#requests-<id>-select[type='button'][phx-click='select'][phx-value-id='<id>']`; click outcome `:369-372` `detail_path(view) == "/older"`, `selected_rows(view) == ["requests-#{older.id}-select"]`; fields `:248-254` exact values (`"PATCH"`, `"/github/push"`, `"b=2&a=%20"`, `"text/plain; charset=utf-8"`, `"198.51.100.4"`, ISO time, `"5 bytes"`); headers `:256-261` four pairs incl. repeated `x-a` in order; context `test/whiq/inspector_test.exs:317` `{:ok, stored}`, `:325` foreign id `{:error, :not_found}`; forged select `test/whiq_web/live/bin_live_test.exs:407-409` page unchanged | PASS |
| LIVE-07 | Valid UTF-8 body displayed as text | `test/whiq_web/live/bin_live_test.exs:269` `body(document) == {["text"], "olá\nmundo"}`; unit `test/whiq_web/byte_format_test.exs:12` `{:text, "olá <script>"}` | PASS |
| LIVE-08 | Non-UTF-8 body displayed as hex dump (16 bytes/line, lowercase, offset column, per spec Assumptions) | `test/whiq_web/live/bin_live_test.exs:277` `{["hex"], "00000000  ff 00 41"}`; unit `test/whiq_web/byte_format_test.exs:16` same, `:28-30` 17 bytes -> two lines, second offset `00000010`, lowercase `0a..0f` | PASS |
| LIVE-09 | Empty body displays "(empty body)" | `test/whiq_web/live/bin_live_test.exs:294-295` `{["empty"], text}`, `String.trim(text) == "(empty body)"`; unit `test/whiq_web/byte_format_test.exs:8` `== :empty` | PASS |
| LIVE-11 | Header names, header values, query strings and bodies rendered as escaped text | `test/whiq_web/live/bin_live_test.exs:310` `LazyHTML.query("#request-detail script") |> Enum.count() == 0`; `:311` query text `== "q=" <> script`; `:312` header name and value text equal the script string; `:313` body `{["text"], script}`; non-UTF-8 `:325` content type `== "text/plain\\xff"`, `:327-330` header value `"\\xff\\x80"`, `:333` `render(view) |> String.valid?()` | PASS |
| LIVE-12 | Page loaded with requests selects the newest | `test/whiq_web/live/bin_live_test.exs:225-226` `#detail-path == "/newer"`, time `== DateTime.to_iso8601(newer.inserted_at)`; `:367` `selected_rows(view) == ["requests-#{newer.id}-select"]` | PASS |
| LIVE-13 | A new arrival keeps the current selection | `test/whiq_web/live/bin_live_test.exs:383-384` after a live capture, `detail_path(view) == "/older"` and only the older row is `aria-current`; empty-bin arrival becomes the selection `:394-395` (design rule, not a spec AC) | PASS |
| LIVE-15 (edge) | Invalid UTF-8 after the first byte -> hex dump of the whole body | `test/whiq_web/live/bin_live_test.exs:286` `{["hex"], "00000000  6f 6b ff"}`; unit `test/whiq_web/byte_format_test.exs:20` `{:hex, "00000000  61 ff"}` | PASS |

**Status**: All 12 ACs covered on the spec outcome. LIVE-01 timestamp format and LIVE-05 command text are not fixed by `spec.md` but are pinned by `design.md:91`; the tests assert those exact values, so they are not spec-precision gaps.

---

## Discrimination Sensor

Run in a detached worktree at `bb0f285` (`/home/gabriel.eurich@koch.intranet/Projects/whiq-verifier-wt`, with `deps`, `_build` and `.env` copied), one mutant at a time, `docker compose -p whiq run --rm app mix test`, reverted with `git checkout -- <file>`. Every mutant compiled and ran the full suite (104 tests); a kill means at least one assertion failed.

| # | File:line | Mutation | Killed by | Killed? |
| - | --------- | -------- | --------- | ------- |
| M1 | `lib/whiq_web/byte_format.ex:12` | `body("")` -> `{:text, ""}` | `byte_format_test.exs:8`, `bin_live_test.exs:294` | Killed |
| M2 | `lib/whiq_web/byte_format.ex:15` | validity checked on the first byte only | `byte_format_test.exs:20`, `bin_live_test.exs:286` | Killed |
| M3 | `lib/whiq_web/byte_format.ex:25` | 8 bytes per line | `byte_format_test.exs:28` | Killed |
| M4 | `lib/whiq_web/byte_format.ex:29` | offset = line index instead of `index * 16` | `byte_format_test.exs:28` | Killed |
| M5 | `lib/whiq_web/byte_format.ex:53` | uppercase hex | 7 tests incl. `byte_format_test.exs:16`, `:40` | Killed |
| M6 | `lib/whiq/inspector.ex:94` | tie-break `asc: r.id` | `inspector_test.exs:294` | Killed |
| M7 | `lib/whiq/inspector.ex:94` | oldest first | `inspector_test.exs:282`, `bin_live_test.exs:119`, `:225` | Killed |
| M8 | `lib/whiq/inspector.ex:93` | list not scoped to the bin | `inspector_test.exs:282` | Killed |
| M9 | `lib/whiq/inspector.ex:103` | fetch not scoped to the bin | `inspector_test.exs:325`, `bin_live_test.exs:407` | Killed |
| M10 | `lib/whiq/inspector.ex:125` | one shared topic for all bins | `inspector_test.exs:270`, `bin_live_test.exs:185` | Killed |
| M11 | `lib/whiq/inspector.ex:76` | broadcast removed | `inspector_test.exs:259`, `bin_live_test.exs:171`, `:195`, `:387` | Killed |
| M12 | `lib/whiq_web/live/bin_live.ex:15` | no subscribe on mount | `bin_live_test.exs:171`, `:195`, `:394` | Killed |
| M13 | `lib/whiq_web/live/bin_live.ex:52` | live arrival inserted `at: -1` | `bin_live_test.exs:171` | Killed |
| M14 | `lib/whiq_web/live/bin_live.ex:47` | arrival always becomes the selection | `bin_live_test.exs:383` | Killed |
| M15 | `lib/whiq_web/live/bin_live.ex:47` | arrival never becomes the selection | `bin_live_test.exs:394` | Killed |
| M16 | `lib/whiq_web/live/bin_live.ex:35` | oldest selected on load | `bin_live_test.exs:225`, `:367` | Killed |
| M17 | `lib/whiq_web/live/bin_live.ex:122` | empty state `@request_count >= 0` | `bin_live_test.exs:154`, `:195` | Killed |
| M18 | `lib/whiq_web/live/bin_live.ex:51` | count not bumped on arrival | `bin_live_test.exs:195` | Killed |
| M19 | `lib/whiq_web/live/bin_live.ex:74` | previous row not re-inserted (old highlight kept) | `bin_live_test.exs:372`, `:384` | Killed |
| M20 | `lib/whiq_web/live/bin_live.ex:59` | `Integer.parse` accepts a trailing suffix (`"12x"`) | `bin_live_test.exs:409` | Killed |
| M21 | `lib/whiq_web/live/bin_live.ex:211` | body rendered with `raw/1` | `bin_live_test.exs:310` | Killed |
| M22 | `lib/whiq_web/live/bin_live.ex:194` | header value rendered with `raw/1` | `bin_live_test.exs:310`, `:327` | Killed |
| M23 | `lib/whiq_web/live/bin_live.ex:186` | header pairs reversed | `bin_live_test.exs:256`, `:312`, `:327` | Killed |
| M24 | `lib/whiq_web/live/bin_live.ex:168` | content type without `ByteFormat.printable/1` | `bin_live_test.exs:325` | Killed |
| M25 | `lib/whiq_web/live/bin_live.ex:165` | query string rendered with `raw/1` | `bin_live_test.exs:310` | Killed |
| M26 | `lib/whiq_web/live/bin_live.ex:192` | header name rendered with `raw/1` | `bin_live_test.exs:310` | Killed |

**Sensor depth**: expanded (hostile-input display path; 26 behavior-level mutants covering every `ByteFormat` branch, ordering and tie-break, bin scoping of list and fetch, broadcast topic and side effect, subscribe on mount, insert position, empty-state condition and count, selection on load / on arrival / on click, select-id validation, escaping of every captured field).
**Isolation**: real-tree `git status --porcelain` was empty before the sensor and empty after `git worktree remove --force` + `git worktree prune` (diffed, identical).
**Result**: 26/26 killed - PASS

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | PASS - three modules touched, no new abstraction beyond `ByteFormat` (required by AD-008 bytea display) |
| Surgical changes | PASS - diff limited to the 6 files in the design plus `spec.md`/`tasks.md` status |
| No scope creep | PASS - no delete, pretty-print, eviction or expiry reaction (all Out of Scope) |
| Matches patterns | PASS - streams with `phx-update="stream"`, ids on key elements, `<.icon>`, `Layouts.app`, Inspector owns all Repo access |
| Spec-anchored outcome check | PASS - every assertion compares an exact spec/design value |
| Per-layer Coverage Expectation met | PASS - unit: every `ByteFormat` branch; context: ordering, tie, scoping, broadcast; LiveView: 1:1 to the 12 ACs |
| Every test maps to a spec requirement | PASS - the one unlabeled LiveView test (forged `select`, `bin_live_test.exs:398`) maps to T7 Done-when; `printable/1` unit tests map to T1 Done-when / LIVE-11 |
| Documented guidelines followed | PASS - `AGENTS.md` (LazyHTML by element id, no `Process.sleep`, `start_supervised!` not needed, `mix precommit`) |

---

## Edge Cases

- [x] LIVE-15: invalid UTF-8 after the first byte -> whole body hex-dumped (`bin_live_test.exs:286`, `byte_format_test.exs:20`)
- [x] Non-UTF-8 header bytes and content type do not crash the JSON diff (`bin_live_test.exs:325-333`)
- [x] Capture between subscribe and list arrives twice: handled by `stream_insert` replacing by DOM id (`bin_live.ex:13-14` comment; not separately tested, no spec AC)

---

## Gate Check

- **Gate command**: `docker compose run --rm app mix precommit` (compile `--warnings-as-errors`, `deps.unlock --unused`, `format`, `test`)
- **Result**: 104 passed, 0 failed, 0 skipped; `format` left the tree clean (porcelain empty after the run)
- **Test count before feature**: 70 (`tasks.md` baseline)
- **Test count after feature**: 104
- **Delta**: +34 (`byte_format_test.exs` 8, `inspector_test.exs` 7, `bin_live_test.exs` 19); no test removed
- **Skipped tests**: none
- **Failures**: none

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| LIVE-01 | Done | Verified |
| LIVE-02 | Done | Verified |
| LIVE-03 | Done | Verified |
| LIVE-05 | Done | Verified |
| LIVE-06 | Done | Verified |
| LIVE-07 | Done | Verified |
| LIVE-08 | Done | Verified |
| LIVE-09 | Done | Verified |
| LIVE-11 | Done | Verified |
| LIVE-12 | Done | Verified |
| LIVE-13 | Done | Verified |
| LIVE-15 | Done | Verified |

---

## Summary

**Overall**: Ready

**Spec-anchored check**: 12/12 ACs matched the spec outcome; 0 spec-precision gaps
**Sensor**: 26/26 mutations killed
**Gate**: 104 passed, 0 failed

**What works**: live list newest first with id tie-break; per-bin broadcast and subscription; empty state with exact `curl`; detail pane with every field and header pair in order; text / hex / empty body classification including LIVE-15; escaping of every captured field, with non-UTF-8 bytes rendered as `\xNN`; selection on load, preserved on arrival, moved on click, forged ids ignored.

**Issues found**: none.

**Next steps**: none for this feature. Lessons: clean PASS, nothing recorded.
