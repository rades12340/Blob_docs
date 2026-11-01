# CORS error or signed out after reload

## Symptoms

- The browser console shows a CORS error for a request to `http://localhost:8080/...`.
- Or the user signs in fine but is signed out again on every page reload.
- Often only on one host: it works at `http://localhost:5173` but not at `http://0.0.0.0:5173`, `127.0.0.1` or a LAN IP.

The current frontend never calls the gateway from the browser. It calls `/api/*` on its own origin, and the Next.js server forwards to the gateway ([ADR 0001](../decisions/0001-same-origin-api-proxy.md)). So a CORS error or a request to `:8080` in the browser means the browser is running an **old build** of the frontend, or an old page from its cache.

!!! tip "See it in Grafana"
    Users who are signed out on reload show up as refreshes without a cookie:

    ```logql
    {container="auth"} | json | message="refresh rejected" | reason="no_cookie"
    ```

    Those are logged at info. If the requests reach the gateway at all, the **Requests per second** panel with `service=gateway` shows them.

## Check

1. In the browser's dev tools, open **Network** and reload. Look at where `refresh` goes.
    - `http://<page host>:5173/api/auth/refresh`: the build is current. Go to step 4.
    - `http://localhost:8080/...`: the page is an old build. Go to step 2.

2. Is the running container older than the code?

    ```bash
    docker inspect blob-frontend-frontend-1 --format '{{.Created}}'
    git -C Blob_frontend log -1 --format='%ci %s'
    ```

    If the container was created before the latest commit, it's stale.

3. Does the running server forward `/api/*`?

    ```bash
    curl -s -X POST localhost:5173/api/auth/refresh
    ```

    `{"error":"Not logged in"}` means the rewrite works. A 404 HTML page means the image predates the rewrite.

4. If the build is current but users are still signed out, check the cookie. In dev tools under **Application → Cookies**, after signing in there should be a `refresh_token` cookie for the page's host. Then check auth is setting it:

    ```bash
    curl -s -i -X POST localhost:5173/api/auth/login -H 'content-type: application/json' \
      -d '{"email":"me@example.com","password":"password123"}' | grep -i set-cookie
    ```

    Use a real test account. You should see `refresh_token=...; HttpOnly; SameSite=Strict`. With `Secure` in it, the browser drops the cookie on plain `http`: auth needs `COOKIE_SECURE=false` locally (its compose file sets it).

## Fix

- **Old build**: rebuild, because `GATEWAY_URL` is read at build time:

    ```bash
    cd Blob_frontend && docker compose up -d --build
    ```

    Then have the user hard-reload (Ctrl+Shift+R, or Cmd+Shift+R on a Mac) so the browser drops the cached page and scripts.

- **Cookie has `Secure` on http**: set `COOKIE_SECURE=false` for auth_service in local development, then `cd auth_service && docker compose up -d`.

Don't fix a CORS error by adding origins to `CORS_ORIGIN` in the gateway. The `SameSite=Strict` refresh cookie still isn't sent cross-site, so users stay signed out.

## Prevent

- Always rebuild the frontend after pulling: `docker compose up -d --build`, not `docker compose restart`.
- Open the app through the frontend's own address. The browser should only ever see one origin. See [Request flow](../architecture/request-flow.md) and [Auth flow](../architecture/auth-flow.md).
