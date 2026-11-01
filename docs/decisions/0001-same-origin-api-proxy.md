# 0001. Same-origin API proxy

## Status

Accepted, 2026-10-18.

## Context

At first the browser called the gateway directly at `http://localhost:8080`. Two problems showed up:

- Opening the app at `http://0.0.0.0:5173` (the "Network" URL that Next prints) failed with a CORS error. The gateway only allowed `CORS_ORIGIN=http://localhost:5173`.
- Allowing more origins wasn't enough. The refresh cookie is `SameSite=Strict`, so the browser doesn't send it when the page's host differs from the API's host. Users were signed out on every reload.

## Decision

The browser only calls `/api/*` on the origin it was loaded from. The Next.js server forwards those requests to the gateway with `rewrites()` in `next.config.ts`:

```ts
{ source: "/api/:path*", destination: `${gatewayUrl}/api/:path*` }
```

`GATEWAY_URL` is read when the app is **built**, so the Docker image takes it as a build argument (`http://gateway:8080` in `compose.yaml`). See [Request flow](../architecture/request-flow.md).

## Consequences

Good:

- No CORS in the browser path at all.
- The refresh cookie is first-party on any host: `localhost`, `127.0.0.1`, `0.0.0.0` or a LAN IP. We checked all three local hosts with Playwright.
- The browser never needs to know where the gateway lives.

Bad:

- Changing `GATEWAY_URL` needs a rebuild (`docker compose up -d --build`), not just a restart. An old build still calls the old address, which is what happened when a user saw the CORS error "after rebuilding". See the runbook [CORS error or signed out](../runbooks/cors-or-signed-out.md).
- Next's rewrite proxy buffers bodies and cut them off at 10 MB by default, silently. A 20,000,211-byte upload reached the gateway as 10,123,616 bytes. We set `experimental.proxyClientMaxBodySize: "30mb"`. See [Upload rejected or cut off](../runbooks/upload-too-large.md).
- Every request has one more hop, and the gateway sees the frontend server's IP. [ADR 0005](0005-trust-proxy.md) deals with that.

## Alternatives considered

- **Allow-list more origins in the gateway**: fixes CORS, but the `SameSite=Strict` cookie still isn't sent cross-site, so users stay signed out.
- **`SameSite=Lax` cookie**: weakens CSRF protection for the refresh endpoint, and still breaks when the page and API hosts differ in more than port.
- **A separate reverse proxy (nginx, Caddy) putting the app and API on one host**: works, but adds a container and config to every environment for what Next already does.
