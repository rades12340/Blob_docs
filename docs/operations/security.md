# Security checklist

What the system already does to protect users and data, and what's still needed before it runs anywhere but a laptop. Each status was checked against the code on each repo's `main`. When you close a "To do", change it here in the same PR.

## Accounts and tokens

| Item | Status | Where |
| --- | --- | --- |
| Passwords hashed with `Bun.password` (Argon2id), 8–256 characters | Done | auth_service `src/routes.ts` |
| Login takes the same time whether or not the email exists, and returns the same `401` | Done | auth_service `src/routes.ts` (`dummyHash`) |
| Access token is a short-lived (15 min) EdDSA JWT with `iss`, `aud`, `exp`, checked by each service | Done | auth_service `src/routes.ts`, Blob_storage `src/auth.ts` |
| Access token kept in memory only, never in `localStorage` | Done | Blob_frontend `lib/api.ts` |
| Refresh token in an `HttpOnly`, `SameSite=Strict` cookie, `Secure` by default | Done | auth_service `src/routes.ts`. Local compose sets `COOKIE_SECURE=false` for http. |
| Refresh tokens stored only as SHA-256 hashes | Done | auth_service `src/routes.ts`, `src/db.ts` |
| Refresh token rotated on every `/refresh`; reusing an old one revokes all the user's sessions | Done | auth_service `src/routes.ts`. [Runbook](../runbooks/refresh-token-reuse.md). |
| Browser calls the API on its own origin, so no cross-site cookies or CORS | Done | Blob_frontend `next.config.ts`. [ADR 0001](../decisions/0001-same-origin-api-proxy.md). |
| Tokens carry a `kid`, and the JWKS endpoint publishes the public key with it | Done | auth_service `src/keys.ts`, `/.well-known/jwks.json` |
| Key rotation: JWKS serves only one key, so access tokens signed with the old key fail (`401`) until the client refreshes | To do | auth_service `src/keys.ts`, `src/routes.ts`. [Runbook](../runbooks/rotate-jwt-key.md). |
| JWT private key in AWS Secrets Manager or SSM Parameter Store, not a `.env` file | To do | auth_service `AUTH_PRIVATE_KEY` |
| `COOKIE_SECURE=true` in every deployed environment (needs TLS) | To do | auth_service compose / deployment config |

## Abuse and exposure

| Item | Status | Where |
| --- | --- | --- |
| Per-IP rate limit at the gateway (`RATE_LIMIT`, 300/min) | Done | Blob_api_gateway `src/rateLimit.ts`, `src/proxy.ts` |
| Register and login limited to 20/min per IP | Done | auth_service `src/rateLimit.ts`, `src/routes.ts` |
| Rate limits shared between instances (Redis) if a service is scaled out | To do | Both `src/rateLimit.ts` files are in memory |
| Client IP taken from `X-Forwarded-For` only with `TRUST_PROXY=true` | Done | Blob_api_gateway `src/proxy.ts`, auth_service `src/routes.ts`. [ADR 0005](../decisions/0005-trust-proxy.md). |
| TLS in front: a reverse proxy or load balancer terminating HTTPS for Blob_frontend | To do | Deployment |
| Only the frontend reachable: don't publish 8080, 4000, 3000 or 9090 | To do | Every `compose.yaml` publishes its port for local debugging |
| Grafana with a login, or not exposed at all | To do | Blob_observability `compose.yaml` (anonymous admin, dev only) |
| Security headers on the frontend (CSP, HSTS, `X-Content-Type-Options`, `frame-ancestors`) | To do | Blob_frontend `next.config.ts` has no `headers()` |
| CORS allows only `CORS_ORIGIN` | Done | Gateway `src/proxy.ts`, auth_service and Blob_storage `src/routes.ts` |
| Containers run as a non-root user | Done | `USER bun` in auth_service, Blob_storage and Blob_api_gateway; `USER node` in Blob_frontend |

## Files and S3

| Item | Status | Where |
| --- | --- | --- |
| Owner isolation: files are stored under `files/<owner>/`, and someone else's id gives `404`, not `403` | Done | Blob_storage `src/storage.ts` (`fileKey`), `src/routes.ts` |
| Upload size limit (`MAX_UPLOAD_BYTES`, 25 MB) | Done | Blob_storage `src/app.ts`, `src/routes.ts` |
| Downloads by presigned URL that expires (`DOWNLOAD_URL_TTL`, 300 s); the bucket stays private | Done | Blob_storage `src/routes.ts`, README "S3 setup" |
| Downloads served as `Content-Disposition: attachment`, so a file never renders as a page | Done | Blob_storage `src/routes.ts` |
| Content type checked from the file's bytes, not trusted from the client | To do | Blob_storage `src/routes.ts` stores `file.type` as sent |
| Least-privilege IAM policy: Put/GetObject on `files/*`, ListBucket only for prefix `files/*` | Done | Blob_storage README "S3 setup", [Running on AWS](aws.md) |
| An IAM role (ECS task role or instance profile) instead of long-lived access keys | To do | Deployment. [Rotate S3 keys](../runbooks/rotate-s3-keys.md) until then. |
| S3 encryption setting reviewed (SSE-S3 by default, or SSE-KMS) and versioning on | To do | Bucket settings |
| Block Public Access on the bucket | Done | Blob_storage README "S3 setup" (step 1) |

## Secrets and logs

| Item | Status | Where |
| --- | --- | --- |
| `.env` git-ignored | Done | `.gitignore` in auth_service and Blob_storage, the two repos that read one |
| Never logged: `Authorization`, cookies, passwords, tokens, query strings, presigned URLs, private keys | Done | `src/log.ts` callers in each service. [Logging](../architecture/logging.md). |
| Emails masked in logs (`m***@example.com`) | Done | auth_service `maskEmail` in `src/routes.ts` |
| Request ids validated (`^[A-Za-z0-9._-]{1,128}$`), so clients can't inject text into logs | Done | Gateway `src/proxy.ts`, both services |
| A real vulnerability-reporting policy | To do | Blob_storage `SECURITY.md` is still GitHub's template |

## Supply chain and CI

| Item | Status | Where |
| --- | --- | --- |
| Lockfiles installed with `--frozen-lockfile`; base images pinned to a version | Done | Every `Dockerfile` and `ci.yml` |
| Dependabot for npm, Docker and GitHub Actions | To do | No `.github/dependabot.yml` in any repo |
| CodeQL code scanning | To do | No workflow yet |
| gitleaks secret scanning in CI | To do | No workflow yet |
| Trivy image scanning in CI | To do | No workflow yet |
| `main` protected; PRs need passing checks | Done | Branch protection. See [Contributing](../contributing.md). |
