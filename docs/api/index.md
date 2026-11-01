# Using the API

Everything goes through the API gateway. This page shows how to call it with curl, what errors look like, and what limits apply. For every field of every endpoint, see the reference pages:

- [Auth API reference](auth.md): register, login, refresh, logout, `/me`, JWKS.
- [Blob API reference](blob.md): upload, list, download links.

## Base URLs

| Address | What it is | Use it for |
| --- | --- | --- |
| `http://localhost:8080/api/auth` | Gateway → auth_service | Normal use |
| `http://localhost:8080/api/blob` | Gateway → Blob_storage | Normal use |
| `http://localhost:8080/health` | The gateway itself | `{"status":"ok"}`, not rate limited |
| `http://localhost:4000` | auth_service directly | Local debugging only |
| `http://localhost:3000` | Blob_storage directly | Local debugging only |
| `http://localhost:9090` | S3Mock, bucket `blobs` | Presigned download links point here locally |
| `http://localhost:5173/api/...` | Blob_frontend's server, which forwards `/api/*` to the gateway | What the browser uses |

The gateway strips the prefix before forwarding, so `GET /api/blob/files` reaches Blob_storage as `GET /files`, and `POST /api/auth/login` reaches auth_service as `POST /login`. Called directly, the services use the paths without a prefix.

Each service also serves Swagger UI at `/docs` and its spec at `/openapi.json`: <http://localhost:4000/docs> and <http://localhost:3000/docs>.

!!! warning "Don't publish 8080, 4000 or 3000 in production"
    The local compose files publish every port so you can debug. In production only Blob_frontend (behind TLS) should be reachable. See the [security checklist](../operations/security.md).

## Walkthrough with curl

You need `curl`, `jq` and the four stacks running (see [Getting started](../getting-started.md)). The commands run from one shell, so the variables carry over.

### 1. Register

```bash
curl -s -X POST localhost:8080/api/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"me@example.com","password":"password123"}'
```

```json
{"id":"191a6044-0f01-4359-b220-037d63286da9","email":"me@example.com"}
```

The password must be 8–256 characters. Registering the same email again returns `409 {"error":"Email already registered"}`.

### 2. Log in and keep the token

```bash
TOKEN=$(curl -s -c cookies.txt -X POST localhost:8080/api/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"me@example.com","password":"password123"}' | jq -r .accessToken)
echo "$TOKEN" | cut -c1-20
```

The response body is `{"accessToken":"…"}`: an EdDSA-signed JWT, valid for 15 minutes. The response also sets the `refresh_token` cookie, which `-c cookies.txt` saves.

Check who you are:

```bash
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/auth/me
```

```json
{"id":"191a6044-0f01-4359-b220-037d63286da9","email":"me@example.com"}
```

### 3. Upload a file

The file goes in a multipart field called `file`:

```bash
echo "hello blob" > hello.txt
FILE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" -F file=@hello.txt \
  localhost:8080/api/blob/upload | tee /dev/stderr | jq -r .id)
```

```json
{
  "id": "a8a97a0f-53b2-45bc-a895-ebff0de9cf29",
  "ownerId": "191a6044-0f01-4359-b220-037d63286da9",
  "name": "hello.txt",
  "size": 11,
  "type": "text/plain;charset=utf-8",
  "sha256": "a0639d03e7e77d7630dffce7bfe26d51813d4c799f13821e5b6786e2736baaed",
  "createdAt": "2026-11-01T21:02:19.749Z"
}
```

`type` is whatever the client sent, or `application/octet-stream` if it sent none.

### 4. List your files

```bash
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/blob/files | jq
```

The response is `{"files":[…]}` with the same fields as the upload response, newest first. You only ever see your own files.

### 5. Get a download link and download

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  localhost:8080/api/blob/download/$FILE_ID | tee link.json | jq
curl -s -o "$(jq -r .name link.json)" "$(jq -r .url link.json)"
sha256sum hello.txt   # compare with .sha256 in link.json
```

```json
{
  "url": "http://localhost:9090/blobs/files/191a…/a8a9…?X-Amz-Algorithm=AWS4-HMAC-SHA256&…&X-Amz-Expires=300&…",
  "expiresAt": "2026-11-01T21:07:19.996Z",
  "name": "hello.txt",
  "size": 11,
  "type": "text/plain;charset=utf-8",
  "sha256": "a0639d03e7e77d7630dffce7bfe26d51813d4c799f13821e5b6786e2736baaed"
}
```

`url` is a presigned S3 link, valid for `DOWNLOAD_URL_TTL` seconds (300 by default). The download goes straight to S3, not through the gateway, so the link itself needs no token. Treat it as a secret until it expires. An unknown id, or another user's id, returns `404`.

### 6. Refresh and log out

```bash
TOKEN=$(curl -s -b cookies.txt -c cookies.txt -X POST localhost:8080/api/auth/refresh | jq -r .accessToken)
curl -s -b cookies.txt -c cookies.txt -X POST localhost:8080/api/auth/logout -o /dev/null -w '%{http_code}\n'   # 204
```

Always save the new cookie (`-c`) when you refresh. The old one is now revoked, and sending it again logs this user out everywhere (see below).

## The refresh cookie in the browser

The browser never holds a long-lived token that JavaScript can read:

| Token | Lifetime | Where it lives |
| --- | --- | --- |
| Access token | 15 min | In memory only, in Blob_frontend's `lib/api.ts`. Sent as `Authorization: Bearer …`. Lost on reload. |
| Refresh token | 14 days | Cookie `refresh_token`: `HttpOnly`, `SameSite=Strict`, `Path=/`, and `Secure` unless `COOKIE_SECURE=false` (the local compose sets `false` because it runs over plain http). |

How it plays out:

- The browser calls `/api/*` on the app's own origin (`:5173`). Blob_frontend's server forwards those calls to the gateway, so the cookie is first-party and `SameSite=Strict` doesn't block it. No CORS is involved.
- **On reload**, the app calls `POST /api/auth/refresh`. The browser sends the cookie and gets a new access token and a new cookie.
- **On a `401`**, the app refreshes once and retries the request. If the refresh fails, it shows the login page.
- **Rotation:** every `/refresh` revokes the old refresh token and sets a new one. If a revoked token is used again, auth_service assumes it was stolen and revokes **all** of that user's sessions. That's why the app shares one in-flight refresh between parallel requests. See the [refresh token reuse runbook](../runbooks/refresh-token-reuse.md).

The gateway's CORS headers (`Access-Control-Allow-Origin: $CORS_ORIGIN`, `Allow-Credentials: true`) only matter for tools that call `:8080` straight from another origin.

## Errors

Errors are JSON with a single `error` string:

```json
{"error":"Invalid email or password"}
```

| Status | When | `error` |
| --- | --- | --- |
| `400` | Register: bad email, or a password outside 8–256 characters | `Invalid email`, `Password must be 8-256 characters` |
| `400` | Upload: no multipart body or no `file` field | `Missing 'file' field` |
| `401` | Login with a wrong email or password (same answer for both) | `Invalid email or password` |
| `401` | Blob routes or `/me` without a valid, unexpired access token | `Unauthorized` |
| `401` | `/refresh` with no, unknown, revoked or reused cookie; `/refresh` with an expired one | `Not logged in`; `Session expired` |
| `404` | Gateway path outside `/api/auth`, `/api/blob` and `/health`; unknown auth_service route | `Not found` |
| `404` | Download of an unknown id or someone else's file | `Not found` |
| `409` | Register with an email that already exists | `Email already registered` |
| `413` | Upload larger than `MAX_UPLOAD_BYTES` (25 MB) | `File is larger than 26214400 bytes` |
| `429` | Over a rate limit (below) | `Too many requests` |
| `500` | A bug in a service | `Internal server error` |
| `502` | The gateway can't reach auth_service or Blob_storage | `Upstream unavailable` |
| `502` | Blob_storage can't reach S3 | `Storage unavailable` |

A few responses don't follow the format:

- A body more than about 1 MB over `MAX_UPLOAD_BYTES` (or over 100 MB at the gateway) is cut off by the server itself: `413` with an empty body. Through the browser app, Next.js's proxy accepts at most 30 MB. See [Upload rejected or cut off](../runbooks/upload-too-large.md).
- An unknown path under `/api/blob/` doesn't give a 404: Blob_storage serves its HTML demo page with `200` for any path it doesn't know.
- `204` responses (`/logout`, preflights) have no body.

When you see a `502`, use the [Gateway returns 502](../runbooks/gateway-502.md) or [S3 unreachable](../runbooks/s3-unreachable.md) runbook. The `error` field tells you which one.

## X-Request-Id

Every response from the gateway, errors and preflights included, has an `X-Request-Id` header. The gateway passes the same id to the service, which puts it on each of its log lines and returns it too.

- Send your own id to make a request easy to find: `curl -H 'X-Request-Id: my-test-1' …`. It's kept if it matches `^[A-Za-z0-9._-]{1,128}$`. Anything else is replaced with a new UUID.
- Quote the id when you report a problem. Paste it into the **Request id** box on the Grafana dashboard to see that request in every service. See [Observability](../operations/observability.md#following-one-request) and [Logging and request ids](../architecture/logging.md).

```bash
curl -si -H 'X-Request-Id: my-test-1' localhost:8080/health | grep -i x-request-id
# X-Request-Id: my-test-1
```

## Rate limits

| Where | Limit | Counts | Key |
| --- | --- | --- | --- |
| Gateway | `RATE_LIMIT` per minute, default `300` | Every request it forwards. Not `/health`, not 404s, not `OPTIONS` preflights. | Client IP |
| auth_service | 20 per minute | `/register` and `/login` together, successful or not | Client IP |

Both are fixed one-minute windows that start with the client's first request, and both answer `429 {"error":"Too many requests"}` without a `Retry-After` header. Wait up to a minute and try again.

The counters are in memory: they reset when the service restarts and aren't shared between instances.

**Client IP.** With `TRUST_PROXY=true` (set in the compose files), the client is the **last** `X-Forwarded-For` entry. Blob_frontend's server appends the browser's address there, and the gateway and auth_service read it. Without `TRUST_PROXY`, the client is the connecting address. With it, anyone who can reach `:8080` directly can choose their own rate-limit key, which is one more reason not to publish that port in production. See [ADR 0005](../decisions/0005-trust-proxy.md).
