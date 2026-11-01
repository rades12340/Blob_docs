# Rotate the JWT signing key

auth_service signs access tokens with one Ed25519 private key, `AUTH_PRIVATE_KEY` in its `.env` (a JSON private JWK with a `kid`). It reads the key once at startup and publishes only that key's public half at `/.well-known/jwks.json`. There's no overlap period: when you change the key, tokens signed with the old one stop being accepted as soon as Blob_storage reloads the key set.

**What users notice**: almost nothing. Refresh tokens are random values stored in auth's database, not signed with the key, so **no one is signed out**. Access tokens signed with the old key get a `401` from the blob service, and the frontend swaps its cookie for a new token and retries automatically. Sign-in and refresh are down for the few seconds auth_service takes to restart (the gateway answers `502` meanwhile).

## Symptoms

Use this runbook when:

- the key may have leaked (a `.env` committed, shared or copied off a machine). Anyone with it can mint access tokens for **any** user, so rotate now;
- someone with access to the key leaves; or
- it's a scheduled rotation.

!!! tip "See it in Grafana"
    After the rotation, old access tokens show up briefly as rejected signatures, then stop:

    ```logql
    {container="blob"} | json | message="auth failed" | reason="invalid signature"
    ```

    A burst for a few minutes is expected. If it doesn't stop, the blob service is still holding an old key set: restart it (Fix, step 5).

## Check

1. Note the current key id that auth publishes:

    ```bash
    curl -s localhost:4000/.well-known/jwks.json
    ```

2. Make sure auth's data volume is there, so refresh tokens survive the restart:

    ```bash
    docker volume ls | grep auth-data
    ```

3. You need Bun on your machine to generate the key (the script isn't in the image):

    ```bash
    cd auth_service && bun install
    ```

## Fix

1. Generate a new key. It prints one `AUTH_PRIVATE_KEY='…'` line with a new random `kid`:

    ```bash
    bun run gen-key
    ```

2. Open `.env` in an editor and replace the existing `AUTH_PRIVATE_KEY=` line with the new one. Keep exactly one such line. Don't keep the old key anywhere if it leaked.

3. Recreate the container so it reads the new `.env` (`docker compose restart` would keep the old environment):

    ```bash
    docker compose up -d --force-recreate auth
    ```

4. Check auth publishes the new `kid`:

    ```bash
    curl -s localhost:4000/.well-known/jwks.json
    docker compose logs --no-log-prefix auth | tail -3      # expect "listening"
    ```

5. Restart the blob service so it drops the old public key:

    ```bash
    cd ../Blob_storage && docker compose restart blob
    ```

    It caches auth's key set. It would fetch it again by itself when it sees a token with an unknown `kid` or when its copy is older than 10 minutes, but it refetches at most once every 30 seconds. A restart avoids both waits: tokens forged with a leaked old key are rejected at once, and new tokens aren't rejected during the cooldown. The blob service is down for a few seconds. Uploads in progress fail and need retrying.

6. Sign in to the app and upload or list a file to confirm the new tokens work.

## Prevent

- Keep `.env` out of Git (`.gitignore` and `.dockerignore` already exclude it) and out of chat and tickets.
- In production, keep the key in a secret store and inject it as the environment variable.
- auth_service supports one key at a time. A rotation with no rejected tokens at all would need the JWKS to serve the old and new public keys for one access-token lifetime (15 minutes). That's a known limitation in its README.
