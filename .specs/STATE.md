# STATE

## Decisions

### AD-001
- **Decision**: Body parsers leave the endpoint and live in the `:browser` pipeline; `Plug.MethodOverride` is removed, since in a pipeline it runs after route matching and would be a no-op. The `/h` capture scope has no pipeline and reads the raw body with `Plug.Conn.read_body/2`.
- **Reason**: Byte-for-byte body fidelity and a recorded method that matches the request line; also keeps hostile multipart input from writing temp files.
- **Trade-off**: Diverges from the generated Phoenix layout; any future non-browser route must opt into its own parsers.
- **Scope**: endpoint, router, every capture-related feature
- **Date**: 2026-10-27
- **Status**: active

### AD-002
- **Decision**: `Plug.Head` stays in the endpoint behind a function plug that skips paths under `/h/`.
- **Reason**: The router matches before pipelines run, so `Plug.Head` cannot move into a pipeline; skipping only the capture prefix keeps HEAD working on HTML pages and records HEAD faithfully.
- **Trade-off**: The endpoint knows the capture path prefix.
- **Scope**: endpoint, capture routes
- **Date**: 2026-10-27
- **Status**: active

### AD-003
- **Decision**: No user accounts; the unguessable bin token is the ownership model.
- **Reason**: Portfolio scope; matches webhook.site/RequestBin usage.
- **Trade-off**: Anyone holding the URL can read the bin; no way to list "my bins" server-side.
- **Scope**: all features
- **Date**: 2026-10-27
- **Status**: active

### AD-004
- **Decision**: The web layer converts `Plug.Conn` into a plain `RequestSnapshot` map; the `Inspector` context never sees `Plug.Conn`.
- **Reason**: Keeps the domain testable without HTTP and isolates transport details (proxy headers, body reading) in the web layer.
- **Trade-off**: One extra translation step per captured request.
- **Scope**: Inspector context, capture controller
- **Date**: 2026-10-27
- **Status**: active

### AD-005
- **Decision**: Each bin has two tokens: `capture_token` (public, `/h/...`) and `view_token` (private, `/bins/...`).
- **Reason**: The capture URL is handed to third-party senders; it must not let them read headers and secrets other senders posted.
- **Trade-off**: Diverges from webhook.site's single URL; the user keeps two URLs and the view URL is unrecoverable if lost.
- **Scope**: bin-creation, request-capture, live-inspection
- **Date**: 2026-10-27
- **Status**: active

### AD-006
- **Decision**: Bins expire as a whole 7 days after creation; an hourly Oban job deletes them and the cascade removes their requests.
- **Reason**: Predictable lifetime and bounded storage, including the `bins` table itself.
- **Trade-off**: A capture URL wired into a real integration stops working after 7 days.
- **Scope**: bin-creation, request-capture, retention
- **Date**: 2026-10-27
- **Status**: active

### AD-007
- **Decision**: Limits never drop a sender's data silently at the HTTP level: oversized bodies are stored truncated with a flag, and a full bin evicts its oldest request (ring buffer of 100). Only the rate limit answers 429.
- **Reason**: In a debugging tool the newest request and its metadata matter more than completeness.
- **Trade-off**: Truncated bodies are incomplete, and eviction needs a transaction that locks the bin row.
- **Scope**: request-capture, abuse-limits, live-inspection
- **Date**: 2026-10-27
- **Status**: active

### AD-008
- **Decision**: Captured request data that a sender controls byte-by-byte (body, header names and values, `content_type`) is stored as `bytea`; headers are a flat `bytea[]` of alternating name/value in received order.
- **Reason**: Bandit accepts obs-text bytes `0x80-0xFF` in header values (RFC 9110 §5.5); `jsonb` and `text` reject non-UTF-8, which would fail the insert and lose the request.
- **Trade-off**: No jsonb queries over headers; readers (live-inspection) must handle non-UTF-8 bytes for display and rebuild pairs from the flat list.
- **Scope**: request-capture, live-inspection
- **Date**: 2026-10-28
- **Status**: active

## Handoff
