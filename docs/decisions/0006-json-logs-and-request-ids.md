# 0006. JSON logs and request ids

## Status

Accepted, 2026-10-24.

## Context

One user action crosses the frontend, the gateway and one or two services. To debug it we need to find all its log lines, and filter them by field without regexes.

## Decision

- Every service writes one JSON object per line on stdout: `time`, `level`, `service`, `message`, plus `requestId` and event fields. `LOG_LEVEL` (`debug`, `info`, `warn`, `error`; default `info`) drops lower levels.
- The gateway accepts an incoming `X-Request-Id` if it matches `^[A-Za-z0-9._-]{1,128}$`, otherwise it generates a UUID. It forwards the id to the service and echoes it in the response. The services do the same check.
- Secrets are never logged: passwords, tokens, the `Authorization` header, cookies, keys, query strings and download URLs. Emails are masked as `u***@example.com`.
- auth_service, Blob_storage and Blob_api_gateway each keep their own small `src/log.ts` rather than sharing a package.

See [Logging](../architecture/logging.md).

## Consequences

Good:

- A user can quote the `X-Request-Id` from a failed response, and one query finds every line for it.
- Loki can filter on any field with `| json` ([ADR 0007](0007-loki-instead-of-elk.md)).
- No dependency, nothing to configure.

Bad:

- Three copies of `log.ts` can drift. A change to the format means three PRs.
- Raw JSON is harder to read in a terminal; use `jq`.

## Alternatives considered

- **pino or winston**: more features than we use, and another dependency in each service.
- **A shared logging package**: couples the repos' release cycles ([ADR 0008](0008-repo-per-service.md)).
- **Plain text lines**: easy to read, hard to filter.
