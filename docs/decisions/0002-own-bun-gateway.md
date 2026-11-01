# 0002. Our own Bun API gateway

## Status

Accepted, 2026-10-12.

## Context

The browser needs one entry point in front of auth_service and Blob_storage. That entry point routes `/api/auth/*` and `/api/blob/*`, rate-limits per client, sets request ids and handles a few headers (`X-Forwarded-For`, CORS, hop-by-hop headers). Off-the-shelf gateways can do all of this, but each brings its own config language, image and failure modes.

## Decision

Blob_api_gateway is a small Bun server, about 200 lines in `src/proxy.ts`:

- `/api/auth/*` goes to `AUTH_URL` (`http://auth:4000`), `/api/blob/*` to `BLOB_URL` (`http://blob:3000`).
- A per-IP fixed-window limit of `RATE_LIMIT` requests per minute (default 300). Over it: `429 {"error":"Too many requests"}`.
- A failed upstream call gives `502 {"error":"Upstream unavailable"}` and the log line `upstream request failed`.
- Request bodies are streamed, up to 100 MB.

## Consequences

Good:

- Same language, tooling (Biome, `bun test`) and CI as the services.
- Request ids, rate limits and header handling are code we fully control and test.
- Tiny image, starts instantly.

Bad:

- We maintain it, including security fixes.
- No clustering, TLS termination, plugins or admin UI. The rate limiter is in memory, so it resets on restart and isn't shared between instances.
- In production it needs something in front for TLS.

## Alternatives considered

- **nginx**: fast and proven, but request ids, JSON logs and per-IP limits mean config and modules outside our stack.
- **Traefik**: good Docker discovery, more moving parts than two routes need.
- **Kong**: a full API platform with a database or declarative config; far more than we need.
