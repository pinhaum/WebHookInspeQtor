# Bin Creation Specification

## Problem Statement

A visitor needs a fresh, unguessable URL to point a webhook at, and a private page to watch what arrives. There are no accounts (AD-003), so the tokens themselves are the access model. The capture URL is shared with third parties (GitHub, Stripe), so it must not grant read access to the bin.

## Goals

- [ ] One click on the home page produces a bin with a capture URL and a private view URL.
- [ ] Knowing the capture URL never reveals the view URL.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Accounts, listing "my bins" | AD-003 |
| Custom responses per bin | Later candidate feature |
| Renaming, deleting or extending a bin | Not needed for the MVP; retention handles cleanup |
| Rate limit on bin creation | `abuse-limits` feature |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Separate tokens | `capture_token` for `/h/...`, `view_token` for `/bins/...` | Senders must not read the bin | y |
| Token format | 24 bytes from `:crypto.strong_rand_bytes/1`, url-safe base64 without padding (32 chars) | 192 bits; short enough for a URL | y |
| Token collision | No retry; unique index turns a collision into a crash | Probability is negligible at 192 bits | y |
| TTL | Bin expires 7 days after creation (`expires_at` column) | User choice: fixed TTL, whole bin | y |
| Copy to clipboard | Browser Clipboard API through a LiveView JS dispatch | Only UI action in the MVP (user choice) | y |
| UI language | English | Portfolio audience (user choice) | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Create a bin ⭐ MVP

**User Story**: As a developer debugging a webhook, I want to create a bin in one click so that I get a URL to receive requests.

**Why P1**: Entry point of the product.

**Acceptance Criteria**:

1. WHEN the visitor clicks "Create bin" on `/` THEN the system SHALL persist a new bin and navigate to `/bins/:view_token` (BIN-01)
2. The system SHALL generate `capture_token` and `view_token` as two different 32-character url-safe base64 strings (BIN-02)
3. WHEN a bin is created THEN the system SHALL set its `expires_at` to exactly 7 days after its `inserted_at` (BIN-03)
4. WHEN the bin page renders THEN the system SHALL display the absolute capture URL `<endpoint url>/h/<capture_token>` (BIN-04)
5. WHEN the bin page renders THEN the system SHALL display the expiry as an ISO 8601 UTC timestamp (BIN-05)
6. WHEN the bin page renders THEN the system SHALL display the notice "Save this page's URL: it is the only way back to this bin." (BIN-06)
7. WHEN the visitor clicks "Copy" next to the capture URL THEN the system SHALL write the capture URL to the clipboard (BIN-07)

**Independent Test**: LiveView test: click "Create bin", follow redirect, assert URL text and expiry.

---

### P1: Private view URL ⭐ MVP

**User Story**: As a bin owner, I want only the view URL to open the bin page so that whoever sends me webhooks cannot read them.

**Why P1**: Captured headers often carry secrets.

**Acceptance Criteria**:

1. IF `/bins/:token` is requested with a token that matches no bin's `view_token` THEN the system SHALL respond 404 (BIN-08)
2. IF `/bins/:token` is requested with a bin's `capture_token` THEN the system SHALL respond 404 (BIN-09)
3. IF `/bins/:view_token` is requested after the bin's `expires_at` THEN the system SHALL respond 404 (BIN-10)
4. The bin page SHALL NOT render the `view_token` anywhere except the browser's own address (BIN-11)

**Independent Test**: ConnTest requests with unknown, capture and expired tokens all get 404.

---

## Edge Cases

- IF the token in `/bins/:token` contains characters outside the url-safe base64 alphabet THEN the system SHALL respond 404 without querying the database (BIN-12)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| BIN-01 | P1: Create a bin | - | Pending |
| BIN-02 | P1: Create a bin | T1, T2 | In progress |
| BIN-03 | P1: Create a bin | T1, T2 | In progress |
| BIN-04 | P1: Create a bin | - | Pending |
| BIN-05 | P1: Create a bin | - | Pending |
| BIN-06 | P1: Create a bin | - | Pending |
| BIN-07 | P1: Create a bin | - | Pending |
| BIN-08 | P1: Private view URL | - | Pending |
| BIN-09 | P1: Private view URL | - | Pending |
| BIN-10 | P1: Private view URL | - | Pending |
| BIN-11 | P1: Private view URL | - | Pending |
| BIN-12 | P1: Private view URL | - | Pending |

**Coverage:** 12 total, 12 mapped to tasks, 0 unmapped

---

## Success Criteria

- [ ] A visitor goes from the home page to a usable capture URL in one click.
- [ ] No test can reach a bin page with anything but its `view_token`.
