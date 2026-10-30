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

No automated gate covers `bin/migrate`; it is verified by hand. On 2026-10-30 the Verifier built the image from `aec1887`, ran `/app/bin/migrate` against a fresh database on the compose network, and found exit 0, all 5 versions in `schema_migrations` and `oban_jobs` present. A second run also exited 0. Check the applied count, not only the exit code: a mutant that migrated 1 of 5 still exited 0.

## Not covered

- The `push` to `main` trigger has not fired yet; it runs when the stacked PRs merge.
