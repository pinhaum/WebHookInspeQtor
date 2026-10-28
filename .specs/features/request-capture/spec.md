# Request Capture Specification

## Problem Statement

The core promise of the inspector is fidelity: what the bin shows must be what the sender sent. Any request, with any method, body or content type, that hits a capture URL must be stored without parsing, normalizing or re-encoding. The web layer turns the connection into a plain snapshot (AD-004) so the domain stays free of `Plug.Conn`.

## Goals

- [ ] Every byte of the body and every header pair sent is recoverable from storage.
- [ ] The sender always gets a fast, predictable response.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Size, count and rate limits | `abuse-limits` feature |
| Real-time display | `live-inspection` feature |
| Custom response status, headers or body | Later candidate feature |
| Original header-name casing | Bandit lowercases names per the Plug spec; HTTP/2 has no casing |
| Decompressing `Content-Encoding` bodies | Fidelity: store what was sent |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Response to the sender | 200 with empty body | Webhook.site-like default; custom responses come later | y |
| Recorded path | Subpath after the token, `"/"` when none | The token is already known from the bin; the subpath is the useful part | y |
| Header storage | Ordered pairs flattened into a `bytea[]` (`[n1, v1, n2, v2, ...]`), AD-008 | Repeated headers are valid HTTP; values may hold obs-text bytes `0x80–0xFF` that jsonb rejects | y |
| Header order | Order as delivered by Bandit in `req_headers` | The adapter is the earliest point we can observe | y |
| Remote IP source | `fly-client-ip` header in prod (configured); socket peer address elsewhere | Deploy target is Fly.io; the header is set by the proxy | y |
| `fly-client-ip` spoofing | Trust the header; DEL-07 tests a forged value after deploy. Fallback if it fails: parse `x-forwarded-for` from the right with the `remote_ip` library | Fly docs do not state whether a client-supplied value is overwritten; community reports say it reflects the real IP. Exposure until tested: the bin-creation rate limit (LIM-09) could be bypassed | y |
| Body read timeout | `Plug.Conn.read_body/2` default of 15 s per read | Library default; senders are servers | y |
| Timestamp | `inserted_at` as `utc_datetime_usec` | Sub-second ordering between bursts | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Capture any request faithfully ⭐ MVP

**User Story**: As a developer, I want every request sent to my capture URL stored exactly as received so that I can trust what I inspect.

**Why P1**: The product's reason to exist.

**Acceptance Criteria**:

1. WHEN a request reaches `/h/:capture_token` of an unexpired bin THEN the system SHALL store exactly one captured request for that bin and respond 200 with an empty body (CAP-01)
2. WHEN a request is captured THEN the system SHALL record the method exactly as sent, including `HEAD`, `OPTIONS` and non-standard methods such as `PROPFIND` (CAP-02)
3. WHEN a request reaches `/h/:capture_token/github/push` THEN the system SHALL record the path `/github/push` (CAP-03)
4. WHEN a request reaches `/h/:capture_token` with no subpath THEN the system SHALL record the path `/` (CAP-04)
5. WHEN a request carries a query string THEN the system SHALL record it raw, without decoding or reordering (CAP-05)
6. WHEN a request carries repeated headers THEN the system SHALL record every pair in received order (CAP-06)
7. WHEN a request carries a body THEN the system SHALL record it byte-for-byte, including bytes that are not valid UTF-8 (CAP-07)
8. WHEN a request body arrives with `Transfer-Encoding: chunked` THEN the system SHALL record the complete de-chunked body (CAP-08)
9. WHEN a request carries a `multipart/form-data`, `application/x-www-form-urlencoded` or `application/json` body THEN the system SHALL record the raw bytes without parsing them (CAP-09)
10. WHEN a request carries `Content-Encoding: gzip` THEN the system SHALL record the compressed bytes as received (CAP-10)
11. WHEN a request is captured THEN the system SHALL record `body_size` equal to the byte size of the stored body (CAP-11)
12. WHEN a request is captured THEN the system SHALL record `content_type` from the `content-type` header, or nil when the header is absent (CAP-12)
13. WHERE a client IP header is configured, the system SHALL record its value as `remote_ip` (CAP-13)
14. WHERE no client IP header is configured, the system SHALL record the socket peer address as `remote_ip` (CAP-14)
15. The `Inspector` context SHALL receive captures as a plain map with no `Plug.Conn` (CAP-15)

**Independent Test**: ConnTest requests for each method/content-type/binary case, then assert the stored row field by field.

---

### P1: Reject captures for missing bins ⭐ MVP

**User Story**: As the operator, I want requests to unknown or expired bins dropped so that storage only holds live bins.

**Why P1**: Without it, any URL under `/h/` writes to the database.

**Acceptance Criteria**:

1. IF the capture token matches no bin THEN the system SHALL respond 404 and store nothing (CAP-16)
2. IF the capture token belongs to a bin past its `expires_at` THEN the system SHALL respond 404 and store nothing (CAP-17)
3. IF a bin's `view_token` is used under `/h/` THEN the system SHALL respond 404 and store nothing (CAP-18)

**Independent Test**: ConnTest requests with unknown, expired and view tokens; captured-request count stays 0.

---

## Edge Cases

- IF reading the body times out THEN the system SHALL respond 408 and store nothing (CAP-19)
- IF the configured client IP header is absent or not a valid IP THEN the system SHALL record the socket peer address (CAP-20)
- WHEN a request has an empty body THEN the system SHALL record an empty binary and `body_size` 0 (CAP-21)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| CAP-01 | P1: Capture any request faithfully | T1,T5 | Pending |
| CAP-02 | P1: Capture any request faithfully | T4,T5 | Pending |
| CAP-03 | P1: Capture any request faithfully | T4,T5 | Pending |
| CAP-04 | P1: Capture any request faithfully | T4,T5 | Pending |
| CAP-05 | P1: Capture any request faithfully | T4,T5 | Pending |
| CAP-06 | P1: Capture any request faithfully | T3,T4,T5 | In Progress |
| CAP-07 | P1: Capture any request faithfully | T3,T4,T5 | In Progress |
| CAP-08 | P1: Capture any request faithfully | T6 | Pending |
| CAP-09 | P1: Capture any request faithfully | T5 | Pending |
| CAP-10 | P1: Capture any request faithfully | T5 | Pending |
| CAP-11 | P1: Capture any request faithfully | T3,T5 | In Progress |
| CAP-12 | P1: Capture any request faithfully | T3,T5 | In Progress |
| CAP-13 | P1: Capture any request faithfully | T4,T7 | Pending |
| CAP-14 | P1: Capture any request faithfully | T4 | Pending |
| CAP-15 | P1: Capture any request faithfully | T3 | Done |
| CAP-16 | P1: Reject captures for missing bins | T2,T5 | In Progress |
| CAP-17 | P1: Reject captures for missing bins | T2,T5 | In Progress |
| CAP-18 | P1: Reject captures for missing bins | T2,T5 | In Progress |
| CAP-19 | P1: Reject captures for missing bins | T6 | Pending |
| CAP-20 | P1: Capture any request faithfully | T4 | Pending |
| CAP-21 | P1: Capture any request faithfully | T3,T4 | In Progress |

**Coverage:** 21 total, 21 mapped to tasks, 0 unmapped

---

## Success Criteria

- [ ] A random binary body round-trips through capture and storage with identical bytes.
- [ ] No captured field is derived from parsed params.
