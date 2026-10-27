# Foundation Specification

## Problem Statement

A freshly generated Phoenix 1.8 app alters requests before the router: `Plug.Parsers` consumes bodies, `Plug.MethodOverride` rewrites POST methods and `Plug.Head` turns HEAD into GET. A webhook inspector must see requests exactly as sent, so the request path for captures has to be free of those plugs before any feature is built on it. The project also needs a reproducible dev environment, since the host has no Elixir or Postgres.

## Goals

- [x] A capture route under `/h/` receives the request with its original method and an unread body.
- [x] `docker compose` is the only host requirement to develop and test.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Storing captured requests | `request-capture` feature |
| Production Dockerfile, CI, deploy | `delivery` feature |
| Remote IP resolution behind a proxy | `request-capture` feature |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Phoenix version | phx_new 1.8.16, LiveView 1.2.x, Bandit adapter | Latest stable on Hex as of 2026-10-27 | y |
| Plug.Head placement | Endpoint function plug that skips `/h/` (AD-002) | Router matches before pipelines run | y |
| Parsers placement | `:browser` pipeline only, `:urlencoded` parser (AD-001) | LiveView forms travel over the socket; no uploads | y |
| `:api` pipeline | Removed | No API in scope | y |
| Dev environment | App and Postgres both in `docker compose` | User choice; nothing installed on the host | y |
| Bind-mount permissions | App container runs as the host UID/GID (`user:` in compose, values from a local `.env`); `HOME` points to a writable path; `deps/` and `_build/` stay in the bind mount, not in named volumes | Tested 2026-10-27: writes as host UID succeed in the project dir; as root they produce `0:0` files; named volumes are created as root. The earlier failure came from mounting the agent's sandboxed `/tmp` | y |
| Capture route stub | Controller responds 200 with empty body for every method | Lets this feature verify the pipeline before persistence exists | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Unaltered capture pipeline ⭐ MVP

**User Story**: As the developer of the inspector, I want requests under `/h/` to reach the router untouched so that later features can record them faithfully.

**Why P1**: Every capture feature depends on it.

**Acceptance Criteria**:

1. WHEN a request with a body reaches `/h/:token` THEN the endpoint SHALL dispatch it to the capture controller with `body_params` unfetched and the full body still readable through `Plug.Conn.read_body/2` (FND-01)
2. WHEN a HEAD request reaches `/h/:token` THEN the capture controller SHALL receive method `"HEAD"` (FND-02)
3. WHEN a POST with urlencoded body `_method=DELETE` reaches `/h/:token` THEN the capture controller SHALL receive method `"POST"` (FND-03)
4. WHEN a request reaches `/h/:token/any/sub/path` THEN the router SHALL dispatch it to the capture controller (FND-04)
5. WHEN a request with a non-standard method such as `PROPFIND` reaches `/h/:token` THEN the router SHALL dispatch it to the capture controller (FND-05)
6. WHEN a HEAD request reaches `/` THEN the application SHALL respond 200 with an empty body (FND-06)
7. WHEN a request reaches `/h/:token` with an `Accept` header of `application/xml` THEN the application SHALL respond 200 (FND-07)

**Independent Test**: `mix test` with ConnTest requests against the stub controller.

---

### P1: Containerized dev environment ⭐ MVP

**User Story**: As a contributor, I want to run the app and its tests with only Docker installed so that setup is one command.

**Why P1**: The host has no Elixir or Postgres.

**Acceptance Criteria**:

1. WHEN `docker compose up` runs on a clean checkout THEN the system SHALL serve the home page at `http://localhost:4000` with code reloading (FND-08)
2. WHEN `docker compose run --rm app mix test` runs THEN the system SHALL execute the test suite against the compose Postgres (FND-09)
3. The project SHALL pass `mix precommit` (compile with warnings as errors, format, test) (FND-10)

**Independent Test**: Fresh clone, run the two commands, see the page and a green suite.

---

## Edge Cases

- WHEN files are created by the app container THEN they SHALL be owned by the host user, not root (FND-11)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| FND-01 | P1: Unaltered capture pipeline | T4 | Done |
| FND-02 | P1: Unaltered capture pipeline | T4 | Done |
| FND-03 | P1: Unaltered capture pipeline | T4 | Done |
| FND-04 | P1: Unaltered capture pipeline | T4 | Done |
| FND-05 | P1: Unaltered capture pipeline | T4 | Done |
| FND-06 | P1: Unaltered capture pipeline | T3 | Done |
| FND-07 | P1: Unaltered capture pipeline | T4 | Done |
| FND-08 | P1: Containerized dev environment | T2 | Done |
| FND-09 | P1: Containerized dev environment | T2 | Done |
| FND-10 | P1: Containerized dev environment | T2 | Done |
| FND-11 | P1: Containerized dev environment | T1, T2 | Done |

**Coverage:** 11 total, 11 mapped to tasks, 0 unmapped

---

## Success Criteria

- [x] All FND tests green in `docker compose run --rm app mix test`.
