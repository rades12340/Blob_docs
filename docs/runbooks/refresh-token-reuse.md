# Refresh token reuse alert

## Symptoms

- auth logs warn `refresh token reuse detected` with a `userId`.
- That user was signed out on every device at once. Their next refresh gets `401 {"error":"Not logged in"}`.

What happened: a refresh token that had already been swapped for a new one was used again. auth_service can't tell who is legitimate, so it revokes **all** of the user's refresh tokens ([ADR 0004](../decisions/0004-jwt-with-rotating-refresh-tokens.md)).

It can mean a stolen token. More often it's innocent:

- Two tabs or windows refreshing at the same moment, so both send the same old cookie.
- A request retried after the cookie was already rotated, for example on a flaky network.
- An old build of the frontend that doesn't share one in-flight refresh.

!!! tip "See it in Grafana"
    The **Refresh token reuse** panel counts these. To see the events and who they hit:

    ```logql
    {container="auth"} | json | message="refresh token reuse detected"
    ```

## Check

1. Who, and how often?

    ```bash
    docker compose -p auth-service logs --no-log-prefix auth | grep 'refresh token reuse detected'
    ```

    One event for one user is usually a race. Many events, or many users, needs a closer look.

2. Pull everything auth logged for that user around that time:

    ```bash
    docker compose -p auth-service logs --no-log-prefix auth | grep '"userId":"<userId>"' | tail -30
    ```

    Look at the `login succeeded` lines just before. Their `clientIp` shows where the user signed in. A `clientIp` you don't expect (a different country, a hosting provider) points to theft. One IP with two refreshes a few milliseconds apart points to a race.

3. Was the gateway passing the real client IP? If every `clientIp` is the same internal address, `TRUST_PROXY` isn't set on the gateway or auth, and step 2 can't tell users apart ([ADR 0005](../decisions/0005-trust-proxy.md)).

4. Is the frontend current? Old builds may not share the refresh.

    ```bash
    grep -n 'refreshing ??=' Blob_frontend/lib/api.ts
    docker inspect blob-frontend-frontend-1 --format '{{.Created}}'
    ```

## Fix

- **A race**: nothing to repair. The user signs in again. If it happens often, find the cause: rebuild an old frontend (`cd Blob_frontend && docker compose up -d --build`), or find the client that retries refresh calls.
- **Likely theft**: the revocation already logged the attacker out too. Their stolen access token still works until it expires, at most 15 minutes. Then:
    1. Ask the user to sign in again and change their password. There is no password-change endpoint yet; until there is, treat the account as compromised.
    2. Check the blob service for what that user's token did in the meantime:

        ```bash
        docker compose -p blob-service logs --no-log-prefix blob | grep '"userId":"<userId>"' | grep -E 'file uploaded|download link issued'
        ```

    3. Look for how the token leaked: an XSS bug in the frontend, a shared machine, malware.

## Prevent

- Keep the frontend's single shared refresh (`lib/api.ts`). Any new client of `/api/auth/refresh` must do the same.
- Keep `TRUST_PROXY=true` on the gateway and auth, so `clientIp` is useful when this fires.
