# Architecture decisions

An architecture decision record (ADR) explains one choice that shapes the system: what problem we had, what we picked, and what it costs us. They're here so nobody has to dig through old PRs to learn why something is the way it is.

## Rules

- One decision per file, named `NNNN-short-title.md`, numbered in order.
- An accepted ADR is not rewritten. If the decision changes, add a new ADR that supersedes it, and set the old one's status to "Superseded by NNNN".
- If code and an ADR disagree, the code is what runs. Fix the docs or open an issue.

## Template

```markdown
# NNNN. Title in a few words

## Status

Accepted, YYYY-MM-DD. (Or: Proposed, Superseded by NNNN.)

## Context

The problem and the forces at play. What was true when we decided.

## Decision

What we do, in one or two short paragraphs.

## Consequences

Good:

- ...

Bad:

- ...

## Alternatives considered

- **Option**: why it lost.
```

## All decisions

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-same-origin-api-proxy.md) | The browser calls `/api/*` on its own origin; Next.js forwards to the gateway | Accepted, 2026-10-18 |
| [0002](0002-own-bun-gateway.md) | Our own small Bun gateway instead of nginx, Traefik or Kong | Accepted, 2026-10-12 |
| [0003](0003-file-listing-in-blob-service.md) | The blob service lists files from S3; no separate store | Accepted, 2026-10-10 |
| [0004](0004-jwt-with-rotating-refresh-tokens.md) | Short EdDSA access tokens in memory, rotating refresh cookie | Accepted, 2026-10-08 |
| [0005](0005-trust-proxy.md) | `TRUST_PROXY` takes the client IP from the last `X-Forwarded-For` entry | Accepted, 2026-10-18 |
| [0006](0006-json-logs-and-request-ids.md) | JSON log lines and `X-Request-Id` in every service | Accepted, 2026-10-24 |
| [0007](0007-loki-instead-of-elk.md) | Loki and Grafana for logs instead of ELK | Accepted, 2026-10-30 |
| [0008](0008-repo-per-service.md) | One Git repo per service | Accepted, 2026-10-05 |
