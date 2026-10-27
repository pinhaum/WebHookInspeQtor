# Live Inspection Specification

## Problem Statement

Debugging a webhook means triggering an event and watching what arrives. The bin page must show captured requests as they land, without reloading, and display hostile, binary or oversized content safely and legibly.

## Goals

- [ ] A captured request appears on every open page of its bin without reload.
- [ ] Any captured content renders without executing or breaking the page.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Deleting or clearing requests from the UI | User choice: copy URL is the only action |
| JSON pretty-printing, syntax highlighting | Fidelity first; raw text is enough for the MVP |
| Replay, custom responses, signature verification | Later candidate features |
| Reacting live to bin expiry while the page is open | Next navigation returns 404; not worth the complexity |
| Pagination | The ring buffer caps a bin at 100 requests |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Transport | `Phoenix.PubSub` topic per bin, LiveView streams | Project requirement; streams keep server memory flat | y |
| Order | Newest first | The latest event is the one being debugged | y |
| Binary display | Hex dump: 16 bytes per line, lowercase, offset column | Readable for binary formats; base64 adds nothing for reading | y |
| Selection | Newest request selected on load; new arrivals do not steal selection | Avoids the detail pane jumping while reading | y |
| Escaping | HEEx escaping only; `raw/1` is never used on captured data | Captured data is hostile input | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: See requests arrive in real time ⭐ MVP

**User Story**: As a developer, I want new requests to appear on the bin page as they arrive so that I can trigger events and watch them immediately.

**Why P1**: The "inspector" experience.

**Acceptance Criteria**:

1. WHEN the bin page loads THEN the system SHALL list the bin's captured requests newest first, each showing method, path, timestamp and body size (LIVE-01)
2. WHEN a request is captured for the bin THEN every open page of that bin SHALL show it at the top of the list without reload (LIVE-02)
3. WHEN a request is captured for another bin THEN the page SHALL NOT change (LIVE-03)
4. WHEN the ring buffer evicts a request THEN every open page of that bin SHALL remove it from the list (LIVE-04)
5. WHILE the bin has no captured requests the page SHALL show an empty state with a `curl` command targeting the bin's capture URL (LIVE-05)

**Independent Test**: LiveView test: mount the page, capture through the context, assert the new row is rendered first.

---

### P1: Inspect one request in detail ⭐ MVP

**User Story**: As a developer, I want to open a captured request and see every recorded field so that I can verify exactly what the sender sent.

**Why P1**: The list alone does not show headers or body.

**Acceptance Criteria**:

1. WHEN the visitor selects a request THEN the system SHALL show its method, path, raw query string, content type, remote IP, timestamp, body size and every header pair in stored order (LIVE-06)
2. WHERE the body is valid UTF-8, the system SHALL display it as text (LIVE-07)
3. IF the body is not valid UTF-8 THEN the system SHALL display it as a hex dump (LIVE-08)
4. WHERE the body is empty, the system SHALL display "(empty body)" (LIVE-09)
5. WHERE `body_truncated` is true, the system SHALL display "Body truncated: showing the first <body_size> bytes" (LIVE-10)
6. The page SHALL render captured header names, header values, query strings and bodies as escaped text (LIVE-11)
7. WHEN the page loads with captured requests THEN the system SHALL select the newest request (LIVE-12)
8. WHEN a new request arrives while another is selected THEN the system SHALL keep the current selection (LIVE-13)

**Independent Test**: LiveView test with a fixture containing `<script>` in headers and body, a binary body and an empty body.

---

## Edge Cases

- IF the selected request is evicted by the ring buffer THEN the system SHALL select the newest remaining request (LIVE-14)
- IF a body contains invalid UTF-8 only after the first byte THEN the system SHALL still use the hex dump for the whole body (LIVE-15)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| LIVE-01 | P1: See requests arrive in real time | - | Pending |
| LIVE-02 | P1: See requests arrive in real time | - | Pending |
| LIVE-03 | P1: See requests arrive in real time | - | Pending |
| LIVE-04 | P1: See requests arrive in real time | - | Pending |
| LIVE-05 | P1: See requests arrive in real time | - | Pending |
| LIVE-06 | P1: Inspect one request in detail | - | Pending |
| LIVE-07 | P1: Inspect one request in detail | - | Pending |
| LIVE-08 | P1: Inspect one request in detail | - | Pending |
| LIVE-09 | P1: Inspect one request in detail | - | Pending |
| LIVE-10 | P1: Inspect one request in detail | - | Pending |
| LIVE-11 | P1: Inspect one request in detail | - | Pending |
| LIVE-12 | P1: Inspect one request in detail | - | Pending |
| LIVE-13 | P1: Inspect one request in detail | - | Pending |
| LIVE-14 | P1: Inspect one request in detail | - | Pending |
| LIVE-15 | P1: Inspect one request in detail | - | Pending |

**Coverage:** 15 total, 0 mapped to tasks, 15 unmapped ⚠️

---

## Success Criteria

- [ ] A `curl` to the capture URL shows up on an open page in under one second locally.
- [ ] No captured content can inject markup into the page.
