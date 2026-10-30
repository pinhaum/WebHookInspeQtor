# Delivery: CI evidence (T10)

Recorded 2026-10-30. The live deploy smoke test (old T9) is out of scope; see the "Live production deploy" row in `spec.md` Out of Scope.

## Green run on the PR (DEL-01, DEL-11)

PR #9 `feat/delivery` → `feat/retention`, run 41092498517, triggered by `pull_request`.

| Job | Result | URL |
| --- | ------ | --- |
| `checks` | success | https://github.com/pinhaum/WebHookInspeQtor/actions/runs/41092498517/job/124189721489 |
| `release-image` | success | https://github.com/pinhaum/WebHookInspeQtor/actions/runs/41092498517/job/124189721001 |

## Red run on a throwaway branch (DEL-02)

Branch `ci/format-check-proof` changed `text(conn, "ok")` to `text( conn,"ok" )` in `lib/whiq_web/controllers/health_controller.ex`. Draft PR #10 against `feat/delivery`, run 41092967640.

| Job | Result | URL |
| --- | ------ | --- |
| `checks` | failure at `mix format --check-formatted` | https://github.com/pinhaum/WebHookInspeQtor/actions/runs/41092967640/job/124191331238 |
| `release-image` | success | https://github.com/pinhaum/WebHookInspeQtor/actions/runs/41092967640/job/124191330941 |

The run is marked failed. PR #10 was closed and `ci/format-check-proof` deleted locally and on the remote.

## Release migrate (DEL-03)

The `release-image` job now runs the packaged `/app/bin/migrate` against an empty Postgres and compares the applied count in `schema_migrations` with the timestamped files in `priv/repo/migrations`.

- Run 41118214092 on `3c73fbb`: `applied=5 expected=5`, success. https://github.com/pinhaum/WebHookInspeQtor/actions/runs/41118214092/job/124277863693
- Run 41117981402 on `4a58d99` failed with `applied=5 expected=6` because the count included `.formatter.exs`. That failure shows the comparison fails the job on a mismatch.

Earlier manual check (Verifier, 2026-10-30, image from `aec1887`): exit 0, 5/5 versions, `oban_jobs` present, second run also exit 0.

## Not covered

- The `push` to `main` trigger has not fired yet; it runs when the stacked PRs merge.
