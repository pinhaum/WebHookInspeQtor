# LESSONS - auto-maintained by scripts/lessons.py

> Machine-owned. Do NOT hand-edit. Changes are overwritten on the next `lessons.py` write.
> Canonical state lives in `.specs/lessons.json`. Edit lessons only via the script.
> promote_threshold=2 distinct features · window_days=45 · quarantine_threshold=2

## Confirmed (load these at Specify/Design)

Corroborated across multiple features. Safe to apply as guidance.

_none_

## Candidates (under observation - do NOT load as guidance yet)

Seen once or not yet corroborated. Tracked, not trusted.

### L-001 - When an AC starts with a user action, assert the triggering control exists with its label, not only the form or route it submits to
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `templates` · harmful: 0
- features: bin-creation
- evidence: validation.md M10 / lib/whiq_web/controllers/page_html/home.html.heex:14 (templates)
- last seen: 2026-10-28T13:15:54Z

### L-002 - Assert that a form trigger is a submit control, not only a button with the right id and label
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `templates` · harmful: 0
- features: bin-creation
- evidence: validation.md M10d / lib/whiq_web/controllers/page_html/home.html.heex:14 (templates)
- last seen: 2026-10-28T13:18:18Z

### L-003 - Assert a fallback with an input that differs from the test harness default, so a hardcoded constant cannot pass
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `tests` · harmful: 0
- features: request-capture
- evidence: M10 lib/whiq_web/capture_snapshot.ex:51 (CAP-14, CAP-20) (tests)
- last seen: 2026-10-28T17:39:31Z

### L-004 - Test method-case fidelity over a real server, because Plug.Test and ConnTest upcase the HTTP method
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `routes` · harmful: 0
- features: request-capture
- evidence: M15 lib/whiq_web/capture_snapshot.ex:17 (CAP-02) (routes)
- last seen: 2026-10-28T17:39:31Z

### L-005 - Name the encoding, case and repetition variants an AC covers when it says raw or exactly as sent
- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `spec` · harmful: 0
- features: request-capture
- evidence: CAP-02, CAP-03, CAP-12 (validation.md spec-precision gaps) (spec)
- last seen: 2026-10-28T17:39:31Z

### L-006 - When a limit is keyed on the client IP, test it with the proxy header configured and a shared peer address, so keying on the raw peer address fails
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `routes` · harmful: 0
- features: abuse-limits
- evidence: validation.md M13 / lib/whiq_web/controllers/bin_controller.ex:11 (LIM-10) (routes)
- last seen: 2026-10-28T20:44:50Z

### L-007 - Give every error branch a controller maps from the domain an HTTP-level test, not only a domain-level one
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `routes` · harmful: 0
- features: abuse-limits
- evidence: validation.md M18 / lib/whiq_web/controllers/capture_controller.ex:17 (routes)
- last seen: 2026-10-28T20:44:50Z

### L-008 - When a cap shrinks a read below the adapter's chunk size, keep a test with an adapter that returns short chunks so the accumulation loop stays exercised
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `routes` · harmful: 0
- features: abuse-limits
- evidence: validation.md M16, M17 / lib/whiq_web/capture_snapshot.ex:44-45 (routes)
- last seen: 2026-10-28T20:44:50Z

### L-009 - Define client IP in the spec wherever an AC keys on it, including the proxy header rule
- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `spec` · harmful: 0
- features: abuse-limits
- evidence: validation.md SP-1 (LIM-09, LIM-10) (spec)
- last seen: 2026-10-28T20:44:50Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
