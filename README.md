# WebHookInspeQtor

Capture any HTTP request on a throwaway URL and watch it arrive live, byte for byte.

[![CI](https://github.com/pinhaum/WebHookInspeQtor/actions/workflows/ci.yml/badge.svg)](https://github.com/pinhaum/WebHookInspeQtor/actions/workflows/ci.yml)

A study project. It is deploy-ready for Fly.io (release image, `fly.toml`, health check) but not deployed: Fly has no free plan that keeps a machine running.

## What it does

1. Create a bin. You get two URLs: a public **capture URL** (`/h/<capture_token>`) to hand to a webhook sender, and a private **view URL** (`/bins/<view_token>`) for yourself.
2. Send anything to the capture URL: any method, any path below it, any body.
3. The view page updates live and shows the method, path, query string, headers, body and client IP of each request.

Bins expire after 7 days. A bin keeps its newest 100 requests, and bodies above 512 KiB are stored truncated and flagged.

## Local setup

Only Docker is required.

```sh
cp .env.example .env   # then set UID and GID to the output of `id -u` and `id -g`
docker compose up
```

The app runs `mix setup` (deps, database, migrations, assets) and serves on http://localhost:4000. Run the test suite with:

```sh
docker compose run --rm app mix test
```

## Architecture

- **Contexts.** `Whiq.Inspector` owns bins and captured requests. The web layer turns a `Plug.Conn` into a plain snapshot map before calling it, so the domain never sees HTTP types.
- **Capture path.** `/h/:token` sits in a router scope with no pipeline. The controller reads the raw body itself, checks the per-bin rate limit, and stores the request in a transaction that locks the bin row and evicts the oldest request once the bin holds 100.
- **Live updates.** After a capture commits, `Inspector` broadcasts `{:request_captured, request}` (and `{:request_evicted, id}`) on the bin's Phoenix PubSub topic. `BinLive` subscribes on mount and streams the list.
- **Retention.** An hourly Oban cron job deletes expired bins; their requests go with them through `ON DELETE CASCADE`. Oban prunes its own finished jobs after 7 days.
- **Single node.** The rate limiter keeps its counters in ETS, PubSub is local, and the Oban cron must run somewhere. `fly.toml` therefore pins exactly one always-on machine.

## Decisions

The full log, with trade-offs, lives in [`.specs/STATE.md`](.specs/STATE.md).

- **AD-001 Raw capture routes.** Body parsers live in the `:browser` pipeline, not the endpoint, and `Plug.MethodOverride` is gone. Captures keep their exact body bytes and their real method.
- **AD-002 HEAD is recorded as HEAD.** `Plug.Head` stays in the endpoint but skips `/h/`, so HTML pages still answer HEAD and captures record it faithfully.
- **AD-003 No accounts.** An unguessable token is the ownership model.
- **AD-004 Snapshot boundary.** The web layer hands the domain a plain `RequestSnapshot` map instead of a `Plug.Conn`.
- **AD-005 Two tokens per bin.** Senders get the capture token only, so they cannot read what other senders posted.
- **AD-006 Whole-bin expiry.** Bins expire 7 days after creation and an hourly job deletes them.
- **AD-007 Never drop data silently.** Oversized bodies are truncated with a flag, and full bins evict their oldest request. Only the rate limit answers 429.
- **AD-008 Bytes, not text.** Bodies, header names and values, and content types are stored as `bytea`, because senders may send non-UTF-8 header bytes.

Deploy assumptions, as configured in `fly.toml` (`fly deploy --ha=false` after `fly apps create`, a Postgres attached as `DATABASE_URL`, and a `SECRET_KEY_BASE` secret):

- **One machine.** The first deploy runs `fly deploy --ha=false`, which creates a single machine; `min_machines_running = 1` and auto-stop off keep it running. `min_machines_running` is a floor, not a cap, so do not scale the app out. This follows from the single-node design above.
- **Failed migrations keep the old release.** Migrations run as Fly's `release_command`. If they fail, Fly aborts the deploy and the previous release keeps serving. This is documented Fly behavior and is not tested here.

## Known fidelity limits

- **Header names are lowercased.** Bandit lowercases them per the Plug spec, and HTTP/2 has no header casing anyway.
- **Plain-HTTP captures are not stored.** Deployed behind Fly, the proxy redirects `http://` to `https://` before the app sees the request. Senders must use the HTTPS capture URL.
