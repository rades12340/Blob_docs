# Runbooks

A runbook is what to do when something specific goes wrong, written for whoever is on call. Each one has four parts:

1. **Symptoms**: what users or alerts see. Find the runbook whose symptoms match.
2. **Check**: commands to run in order. Each step tells you what a good and a bad result look like. Stop at the first bad one.
3. **Fix**: what to do about what you found.
4. **Prevent**: what keeps it from coming back.

Each runbook also has a tip pointing at the Grafana panel or LogQL query that shows the problem. Grafana runs at <http://localhost:3001> once Blob_observability is up; see [Observability](../operations/observability.md).

## Before you start

- The commands assume the repos are cloned side by side (`auth_service/`, `Blob_storage/`, `Blob_api_gateway/`, `Blob_frontend/`, `Blob_observability/`) and that you run them from the parent folder unless a step says `cd`.
- Compose project names and default container names:

    | Repo | Project | Service | Container | Port |
    | --- | --- | --- | --- | --- |
    | auth_service | `auth-service` | `auth` | `auth-service-auth-1` | 4000 |
    | Blob_storage | `blob-service` | `blob`, `s3` | `blob-service-blob-1` | 3000, S3Mock 9090 |
    | Blob_api_gateway | `api-gateway` | `gateway` | `api-gateway-gateway-1` | 8080 |
    | Blob_frontend | `blob-frontend` | `frontend` | `blob-frontend-frontend-1` | 5173 |

- Start order is auth → Blob_storage → gateway → frontend. auth_service's stack creates the `blob-storage` network that every other stack joins.
- Ask the user for the `X-Request-Id` of a failed response. It's on every log line of that request in every service.

## The runbooks

| Runbook | Use it when |
| --- | --- |
| [Gateway returns 502](gateway-502.md) | Calls fail with `502 {"error":"Upstream unavailable"}`, or the frontend's `/api/*` gives 500 |
| [CORS error or signed out after reload](cors-or-signed-out.md) | The browser console shows a CORS error, or users lose their session on every reload |
| [Upload rejected or cut off](upload-too-large.md) | Uploads fail with 413, or stored files are smaller than the original |
| [S3 unreachable](s3-unreachable.md) | Blob calls fail with `502 {"error":"Storage unavailable"}` |
| [Refresh token reuse alert](refresh-token-reuse.md) | auth logs `refresh token reuse detected`, or a user was signed out everywhere |
| [Rotate the JWT signing key](rotate-jwt-key.md) | Scheduled rotation, or the signing key may have leaked |
| [Rotate S3 access keys](rotate-s3-keys.md) | Scheduled rotation, or an S3 access key may have leaked |
