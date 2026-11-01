# 0004. Short-lived JWTs with rotating refresh tokens

## Status

Accepted, 2026-10-08.

## Context

Blob_storage (and todos_service) must check who is calling on every request without asking auth_service each time. Tokens must be hard to steal from the browser, and a stolen one must stop working soon.

## Decision

- **Access token**: an EdDSA (Ed25519) JWT, valid 15 minutes, with `aud` set from `AUTH_AUDIENCE`. The frontend keeps it in memory only.
- **Refresh token**: a random value stored hashed in SQLite, valid 14 days, in the `httpOnly`, `SameSite=Strict` cookie `refresh_token`. It is replaced on every `/refresh`.
- **Reuse detection**: if a refresh token that was already replaced is used again, auth_service revokes **all** of that user's sessions and logs warn `refresh token reuse detected`.
- Blob verifies tokens itself against auth's public keys at `/.well-known/jwks.json`, with audience `blob_storage`.
- The frontend shares one in-flight refresh between concurrent calls, so it doesn't trip reuse detection itself.

See [Auth flow](../architecture/auth-flow.md).

## Consequences

Good:

- JavaScript can't read the refresh token, and the access token isn't in any storage an XSS payload could dump.
- A stolen access token works for at most 15 minutes.
- A stolen refresh token is caught the moment either party uses an old one.
- No call to auth_service per request.

Bad:

- Reuse detection also fires on innocent races: two tabs refreshing at once, or a request retried after the cookie was already rotated. The user is then signed out everywhere. See [Refresh token reuse alert](../runbooks/refresh-token-reuse.md).
- An access token can't be revoked before it expires.
- auth_service holds one signing key at a time, so rotating it is a manual procedure. See [Rotate the JWT signing key](../runbooks/rotate-jwt-key.md).

## Alternatives considered

- **Server-side sessions**: every service would have to ask auth_service (or a shared store) on each request.
- **Long-lived JWTs**: simple, but a stolen token works for days and can't be revoked.
- **Tokens in `localStorage`**: any XSS can read and send them.
