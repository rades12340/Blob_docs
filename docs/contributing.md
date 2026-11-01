# Contributing

The system is six repos (five services and stacks, plus these docs). They share one set of PR rules, one log format and one Docker network. This page covers the rules, how to add a service, and when to update these docs.

## PR rules

`main` is protected in every repo: changes reach it only through a pull request, and the required checks must pass.

| Rule | Example |
| --- | --- |
| Branch named `<type>/<issue number>-short-slug`: type is `feat`, `fix`, `docs` or `chore`; the slug is lowercase letters, digits and hyphens | `feat/12-refresh-rotation`, `docs/5-api-operations` |
| At least one type label: `feature`, `enhancement`, `bug` or `documentation`. None of `wontfix`, `invalid`, `duplicate`. | `documentation` |
| References an **open issue** (not a PR) | `Closes #12` in the description, `#12` in the title, or the number in the branch name |

Pick the label from what the diff does:

| Change | Label | Branch type |
| --- | --- | --- |
| New capability | `feature` | `feat` |
| Improves existing behaviour, refactor, tooling | `enhancement` | `feat` or `chore` |
| Fixes broken behaviour | `bug` | `fix` |
| Only README or docs | `documentation` | `docs` |

## The four required checks

| Check | Workflow | Passes when |
| --- | --- | --- |
| **labels** | `pr-checks.yml` | The PR has a type label and no blocking one. Re-runs when labels change. |
| **issue** | `pr-checks.yml` (`scripts/check-issue.ts`) | A `#N` in the title or description, or the branch's number, is an open issue. Re-runs when the description is edited. |
| **branch-name** | `branch-name.yml` | The branch matches the pattern below. A branch can't be renamed on an open PR: push to a new branch and open a new PR. |
| The repo's CI job | `ci.yml` | See below. |

The branch-name pattern:

```text
^(feat|fix|docs|chore)/[0-9]+-[a-z0-9][a-z0-9-]*$
```

| Repo | CI job | What it runs |
| --- | --- | --- |
| auth_service, Blob_api_gateway | **Lint, typecheck, test** | `bunx biome ci .`, `bun run typecheck`, `bun test` |
| Blob_frontend | **Lint, typecheck, test** | The same, plus `bun run build` |
| Blob_storage | **Lint, typecheck, test** | The same as auth_service. Runs on PRs and pushes to `main` only. |
| Blob_observability | **Validate, smoke test** | `scripts/validate.sh`, then `scripts/smoke.sh --down` (starts the stack and checks a log line reaches Loki) |
| Blob_docs | **Build** | `./scripts/fetch-openapi.sh`, `mkdocs build --strict`, markdownlint |

!!! note "Blob_storage has three, not four"
    Blob_storage has no `branch-name.yml` and its pre-push hook doesn't check the branch name, so only labels, issue and CI apply there. Name the branch the same way anyway.

### Local hooks

The four Bun repos (auth_service, Blob_storage, Blob_api_gateway, Blob_frontend) use Husky. On commit, `lint-staged` runs Biome on the staged files. On push, the hook runs `bun run typecheck && bun test`, and, except in Blob_storage, rejects a badly named branch first. Don't skip them with `--no-verify`: CI runs the same checks. Blob_observability and Blob_docs have no hooks: run their checks yourself before pushing.

```bash
bun run lint:fix && bun run typecheck && bun test        # Bun repos
./scripts/validate.sh                                    # Blob_observability
./scripts/fetch-openapi.sh && mkdocs build --strict && npx markdownlint-cli2 "docs/**/*.md"   # Blob_docs
```

### The ship-pr skill

Every repo has `.claude/skills/ship-pr/SKILL.md`. With Claude Code, say "ship this" or "open a PR" and it:

1. finds or creates the issue,
2. picks the label from the diff,
3. creates or renames the branch to `<type>/<issue>-slug`,
4. commits with `Closes #N`,
5. pushes and opens the PR,
6. watches the checks and fixes failures, including labels or issue references on an existing PR.

It follows the same rules as this page, so the PR passes on the first try.

## Adding a service

A new service has to fit into four things: the log contract, the compose setup, the gateway, and the log stack. Use Blob_storage or auth_service as the template.

### 1. Follow the log contract

One JSON object per line on stdout. Copy `src/log.ts` from an existing service.

| Field | Rule |
| --- | --- |
| `time` | ISO 8601 |
| `level` | `debug`, `info`, `warn` or `error`, filtered by `LOG_LEVEL` (default `info`) |
| `service` | A short name, for example `"todos"` |
| `message` | A fixed, lowercase event name such as `file uploaded`. Data goes in fields, never in the message. |
| `requestId` | On every line written while handling a request. Take `X-Request-Id` if it matches `^[A-Za-z0-9._-]{1,128}$`, otherwise generate a UUID. Return it in the `X-Request-Id` response header, on errors too. |

- Write one access line per request with message `request` and fields `method`, `route` (the route **pattern**, never the URL), `status`, `ms`, and `userId` when authenticated. The dashboard's request, error and latency panels read exactly these.
- Never log the `Authorization` header, cookies, passwords, tokens, query strings, presigned URLs or keys. Mask emails.

See [Logging and request ids](architecture/logging.md) for the full contract.

### 2. Compose: name, network, labels, log rotation

```yaml
# compose.yaml in the new repo
name: todos-service              # the compose project: becomes the `project` label

services:
  todos:                         # the compose service: becomes the `container` label
    build: .
    ports:
      - "5000:5000"              # local debugging only
    environment:
      LOG_LEVEL: info
      AUTH_ISSUER: http://localhost:4000
      AUTH_JWKS_URL: http://auth:4000/.well-known/jwks.json
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - blob-storage

networks:
  blob-storage:
    external: true               # created by auth_service's stack
```

Alloy reads labels from Docker Compose, so the `name:` and the service name matter. Run the container as a non-root user (`USER bun` in the Dockerfile).

If the service accepts access tokens, verify them against auth_service's JWKS (see Blob_storage's `src/auth.ts`) and add its audience to auth_service's `AUTH_AUDIENCE`.

### 3. Route it through the gateway

In Blob_api_gateway:

- add the prefix to `upstreams` in `src/app.ts`, for example `"/api/todos": env.TODOS_URL ?? "http://localhost:5000"`,
- set `TODOS_URL: http://todos:5000` in its `compose.yaml`,
- add a test in `src/app.test.ts` and a row to its README.

The gateway strips the prefix, so the service serves `/items`, not `/api/todos/items`. Blob_frontend needs no change: it forwards all of `/api/*`.

### 4. Add it to the log stack

In Blob_observability:

- add the compose project name to the `keep` regex in `alloy/config.alloy`: `"auth-service|blob-service|api-gateway|blob-frontend|todos-service"`,
- add the container name to the dashboard's **Service** variable in `grafana/dashboards/blob-system.json` (both `query` and `allValue`),
- run `./scripts/validate.sh`.

### 5. Document it

Open a PR here with the new architecture details, an `openapi.yaml` fetch line in `scripts/fetch-openapi.sh`, a reference page, and the nav entry in `mkdocs.yml`.

## When to update these docs

The service READMEs cover how to run and change one repo. This site covers what spans repos. When a PR in a service repo changes one of these, open a matching PR here:

| You changed | Update |
| --- | --- |
| An endpoint, a request or response field, a status code | `openapi.yaml` in the service repo (the reference pages pick it up), and [Using the API](api/index.md) if the walkthrough or error table changes |
| A port, prefix, env var or default | [Getting started](getting-started.md), [Using the API](api/index.md), the architecture page it belongs to |
| A log event, field or the log contract | [Logging and request ids](architecture/logging.md), and the [Observability](operations/observability.md) recipes and alerts |
| A dashboard panel or the Alloy config | [Observability](operations/observability.md) |
| A security control, done or added | The [security checklist](operations/security.md) |
| S3 settings or the IAM policy | [Running on AWS](operations/aws.md) |
| A design decision | A new ADR in `docs/decisions/`. Don't rewrite an accepted one: supersede it. |
| How something fails or is fixed | The matching runbook in `docs/runbooks/` |
| PR rules, checks or hooks | This page |

Reference the service PR in the docs PR, and keep the docs PR to facts that are true on `main` once both merge.
