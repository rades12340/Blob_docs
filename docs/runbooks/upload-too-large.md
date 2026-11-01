# Upload rejected or cut off

## Symptoms

- The app says "That file is too large (max 25 MB)." before uploading. That's the frontend's own check against `NEXT_PUBLIC_MAX_UPLOAD_BYTES`, and it's working as intended.
- An upload fails with `413` and `{"error":"File is larger than 26214400 bytes"}`.
- Or, worse, an upload "succeeds" but the stored file is smaller than the original and its `sha256` doesn't match.

The limits along the path, from the browser in:

| Where | Limit | Over it |
| --- | --- | --- |
| Frontend, in the browser | `NEXT_PUBLIC_MAX_UPLOAD_BYTES`, default 26214400 (25 MB), set at build time | Error shown, nothing sent |
| Next.js rewrite proxy | `experimental.proxyClientMaxBodySize: "30mb"` in `next.config.ts` (Next's default is 10 MB) | Body is **cut off silently** |
| Gateway | 100 MB | Bun rejects with 413 |
| Blob_storage server | `MAX_UPLOAD_BYTES` + 1 MB for the multipart envelope | Bun rejects with 413 before the handler, so no log line |
| Blob_storage handler | `MAX_UPLOAD_BYTES`, default 26214400 (25 MB) | `413`, log warn `upload rejected` with `reason: "too large"` |

!!! tip "See it in Grafana"
    ```logql
    {container="blob"} | json | message="upload rejected"
    ```

    The `reason` and `size` fields show what was rejected. 413s that Bun rejects before the handler don't log; look for `status=413` on the gateway's `request` lines instead:

    ```logql
    {container="gateway"} | json | message="request" | status=413
    ```

## Check

1. How big is the file, exactly?

    ```bash
    stat -c %s myfile.bin        # macOS: stat -f %z myfile.bin
    ```

2. What limit does the blob service run with?

    ```bash
    docker inspect blob-service-blob-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep MAX_UPLOAD || echo "default: 26214400"
    ```

3. Is the frontend build allowing more than 10 MB through its proxy? Look for the setting in the source the image was built from:

    ```bash
    grep -n proxyClientMaxBodySize Blob_frontend/next.config.ts
    docker inspect blob-frontend-frontend-1 --format '{{.Created}}'
    ```

    If the line is missing, or the container is older than the commit that added it, uploads over 10 MB get truncated.

4. Upload the same file directly to the gateway and through the frontend, and compare `size` and `sha256` in the responses with the file's own:

    ```bash
    sha256sum myfile.bin
    TOKEN=...   # an access token, e.g. from POST localhost:8080/api/auth/login
    curl -s -H "Authorization: Bearer $TOKEN" -F file=@myfile.bin localhost:8080/api/blob/upload
    curl -s -H "Authorization: Bearer $TOKEN" -F file=@myfile.bin localhost:5173/api/blob/upload
    ```

    If the gateway copy is right and the frontend copy is smaller, the Next.js proxy is truncating.

## Fix

- **File over 25 MB**: expected. To allow bigger files, raise all three together: `MAX_UPLOAD_BYTES` in Blob_storage, `NEXT_PUBLIC_MAX_UPLOAD_BYTES` (a build arg) and `proxyClientMaxBodySize` in Blob_frontend. The proxy limit must stay above the blob limit, or files get cut off instead of rejected.
- **Truncated uploads**: rebuild the frontend from current `main`, which sets `proxyClientMaxBodySize: "30mb"`:

    ```bash
    cd Blob_frontend && git pull && docker compose up -d --build
    ```

    Truncated files already stored are corrupt. Ask the users to upload them again.

## Prevent

- Keep the limits ordered: frontend check ≤ `MAX_UPLOAD_BYTES` < Next proxy limit ≤ gateway limit.
- Blob returns `sha256` for every upload. Compare it in tests that cross the proxy.
