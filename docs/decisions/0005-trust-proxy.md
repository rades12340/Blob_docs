# 0005. Trust the proxy's X-Forwarded-For

## Status

Accepted, 2026-10-18.

## Context

After [ADR 0001](0001-same-origin-api-proxy.md), every browser request reaches the gateway from the Next.js server. The socket address is the same for everyone, so per-IP rate limits (the gateway's `RATE_LIMIT`, auth's login limit) would be one shared bucket for all users. The Next.js proxy appends the browser's address to `X-Forwarded-For`.

## Decision

`TRUST_PROXY=true` tells a service to take the **last** `X-Forwarded-For` entry as the client IP:

- **Gateway**: uses the last entry for its rate limit and logs, and forwards the chain unchanged. With `TRUST_PROXY=false` it uses the socket address and appends it.
- **auth_service**: uses the last entry for its limit of 20 requests per minute per IP on `/register` and `/login`, and for `clientIp` in logs.

The default is `false` in both. The compose files set it to `"true"`.

## Consequences

Good:

- Each browser gets its own rate-limit bucket.
- Logs show the real client IP.

Bad:

- Anyone who can reach the gateway directly on port 8080 can set `X-Forwarded-For` and pick their own IP, dodging the rate limit. **Don't publish port 8080 in production**: only the frontend should reach the gateway. Same for auth's port 4000.
- Each hop must append exactly one entry. Putting another proxy in front changes which entry is the client.

## Alternatives considered

- **Leave it off**: all users share one bucket; one busy user rate-limits everyone.
- **Take the first entry**: the first entry is whatever the client sent, so it's trivially spoofable even through the proxy.
- **A configurable count of trusted hops**: more general, not needed with one proxy.
