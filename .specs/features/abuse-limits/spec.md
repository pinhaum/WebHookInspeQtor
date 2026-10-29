# Abuse Limits Specification

## Problem Statement

A public endpoint that stores whatever it receives is an invitation to fill the database. The inspector needs bounds on body size, requests per bin, capture rate and bin creation, chosen so that legitimate webhook traffic (GitHub, Stripe payloads of tens of KB) is never affected.

## Goals

- [ ] Worst-case storage per bin is bounded at about 50 MB (100 x 512 KB).
- [ ] A flood against one bin cannot degrade other bins.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Per-IP limit on captures | Webhook providers share IPs (user choice: per bin only) |
| Distributed rate limiting across nodes | Single Fly machine; ETS backend is enough |
| Captcha or proof-of-work on bin creation | Disproportionate for the MVP |
| Configuring limits through env vars | Fixed values; app config exists so tests can lower them |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Oversized body | Store the first 524,288 bytes with `body_truncated = true`, respond 200 | User choice: keep the request visible | y |
| `body_size` on truncation | Bytes stored; the sender's `content-length` header still shows the declared size | Reading the rest only to count it costs bandwidth for no value | y |
| Full bin | Delete the oldest request so the bin keeps 100 (ring buffer) | User choice: newest requests matter | y |
| Concurrency on the ring buffer | Insert and eviction in one transaction that locks the bin row | Parallel captures must not exceed 100 | y |
| Capture rate | 60 per minute per bin, fixed window | User choice: conservative | y |
| Bin creation rate | 10 per hour per client IP | User choice: conservative | y |
| Rate limit library | Hammer (7.x, ETS backend) | Actively maintained; PlugAttack last released 2021 | y |
| Header count, header size, request line | Bandit defaults | Server-level limits already exist; no reason to duplicate | y |
| Where limits live | `config/config.exs`, overridden in `config/test.exs` | Tests need small limits | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Bounded body size ⭐ MVP

**User Story**: As the operator, I want oversized bodies cut at a fixed size so that one request cannot consume unbounded storage.

**Why P1**: Single largest storage risk.

**Acceptance Criteria**:

1. IF a request body exceeds 524,288 bytes THEN the system SHALL store its first 524,288 bytes, set `body_truncated` to true and respond 200 (LIM-01)
2. WHEN a request body is exactly 524,288 bytes THEN the system SHALL store it whole with `body_truncated` false (LIM-02)
3. WHERE `body_truncated` is true, the bin page SHALL display "Body truncated: showing the first <body_size> bytes" (LIVE-10)

**Independent Test**: Capture a 524,289-byte body and assert stored size and flag.

---

### P1: Ring buffer per bin ⭐ MVP

**User Story**: As the operator, I want each bin capped at 100 requests so that a busy bin stays bounded while still showing the newest traffic.

**Why P1**: Bounds storage per bin.

**Acceptance Criteria**:

1. WHEN a capture arrives for a bin holding 100 requests THEN the system SHALL store it and delete the bin's oldest request (LIM-03)
2. WHEN 20 captures arrive concurrently for a bin holding 95 requests THEN the system SHALL leave exactly 100 requests, the 100 newest (LIM-04)
3. WHEN a request is evicted THEN the system SHALL broadcast the eviction on the bin's topic (LIM-05)
4. WHEN the ring buffer evicts a request THEN every open page of that bin SHALL remove it from the list (LIVE-04)

**Independent Test**: Fill a bin to the cap, capture one more, assert count and which id was removed.

---

### P1: Capture rate limit ⭐ MVP

**User Story**: As the operator, I want a per-bin capture rate so that a flood against one bin cannot saturate the database.

**Why P1**: Protects shared resources.

**Acceptance Criteria**:

1. IF a bin receives a 61st capture within the same one-minute window THEN the system SHALL respond 429 with a `retry-after` header in seconds and store nothing (LIM-06)
2. WHEN the window resets THEN the system SHALL accept captures for that bin again (LIM-07)
3. WHILE one bin is rate limited the system SHALL keep accepting captures for other bins (LIM-08)

**Independent Test**: With a test limit of 2/window, the third capture gets 429; another bin still gets 200.

---

### P1: Bin creation rate limit ⭐ MVP

**User Story**: As the operator, I want bin creation limited per IP so that a script cannot create bins in bulk.

**Why P1**: Bins are the unit of storage.

**Acceptance Criteria**:

1. IF a client IP requests an 11th bin within the same hour THEN the system SHALL create no bin and show "Too many bins created. Try again later." (LIM-09)
2. WHILE one IP is limited the system SHALL keep allowing bin creation from other IPs (LIM-10)

"Client IP" in LIM-09 and LIM-10 is the address resolved per design.md (`WhiqWeb.ClientIP`): the configured proxy header (`fly-client-ip` in prod) when it holds a valid IP, otherwise the peer address, written in canonical form (`:inet.ntoa/1`) so two spellings of one address share a quota. The same canonical value is what capture records as `remote_ip` (CAP-13); the raw header stays in the stored headers. A header value that is not a valid IP, including one with non-UTF-8 bytes, falls back to the peer address (CAP-20).

**Independent Test**: With a test limit of 1/window, the second click from the same IP shows the message.

---

## Edge Cases

- WHEN a truncated capture also triggers eviction THEN the system SHALL apply both in the same transaction (LIM-11)
- IF a capture is rejected by the rate limit THEN the system SHALL NOT evict any request (LIM-12)
- IF the selected request is evicted by the ring buffer THEN the bin page SHALL select the newest remaining request (LIVE-14)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| LIM-01 | P1: Bounded body size | T1,T2,T6 | Done |
| LIM-02 | P1: Bounded body size | T2,T6 | Done |
| LIM-03 | P1: Ring buffer per bin | T3 | Done |
| LIM-04 | P1: Ring buffer per bin | T3 | Done |
| LIM-05 | P1: Ring buffer per bin | T3 | Done |
| LIM-06 | P1: Capture rate limit | T7 | Done |
| LIM-07 | P1: Capture rate limit | T4 | Done |
| LIM-08 | P1: Capture rate limit | T7 | Done |
| LIM-09 | P1: Bin creation rate limit | T8,T11,T14,T15 | Done |
| LIM-10 | P1: Bin creation rate limit | T5,T8,T11,T14,T15 | Done |
| LIM-11 | P1: Ring buffer per bin | T2,T3 | Done |
| LIM-12 | P1: Capture rate limit | T7 | Done |
| LIVE-04 | P1: Ring buffer per bin (moved from live-inspection) | T9 | Done |
| LIVE-10 | P1: Bounded body size (moved from live-inspection) | T10 | Done |
| LIVE-14 | P1: Ring buffer per bin (moved from live-inspection) | T9 | Done |

**Coverage:** 15 total, 15 mapped to tasks, 0 unmapped

---

## Success Criteria

- [ ] Concurrency test proves the ring buffer never exceeds its cap.
- [ ] Every limit has a test that hits it and one that stays just under it.
