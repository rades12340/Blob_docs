# Gateway returns 502

## Symptoms

- API calls fail with `502` and the body `{"error":"Upstream unavailable"}`.
- The gateway logs error `upstream request failed`, with `upstream` set to `auth` or `blob`.
- In the app, sign-in or the file list fails for everyone.

Two look-alikes that are **not** this runbook:

- `500` from the frontend's own `/api/*`: the frontend server can't reach the gateway. Go to step 5.
- `502 {"error":"Storage unavailable"}`: the blob service is up but S3 isn't. See [S3 unreachable](s3-unreachable.md).

!!! tip "See it in Grafana"
    The **Gateway 502s** panel on the "Blob storage system" dashboard counts these. In Explore:

    ```logql
    {container="gateway"} | json | message="upstream request failed"
    ```

    The `upstream` field tells you which service failed.

## Check

1. Find which upstream fails:

    ```bash
    docker compose -p api-gateway logs --no-log-prefix gateway | grep 'upstream request failed' | tail -5
    ```

    `"upstream":"auth"` or `"upstream":"blob"`, and the `error` text (connection refused, unable to resolve host) tell you where to look.

2. Are all stacks running?

    ```bash
    docker compose ls
    ```

    You should see `auth-service`, `blob-service`, `api-gateway` and `blob-frontend` as `running`. A missing one is your cause.

3. Is every container on the `blob-storage` network?

    ```bash
    docker network inspect blob-storage --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'
    ```

    You need `auth-service-auth-1`, `blob-service-blob-1`, `api-gateway-gateway-1` and `blob-frontend-frontend-1`.

4. Does the gateway point at the right addresses?

    ```bash
    docker inspect api-gateway-gateway-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep _URL
    ```

    Expect `AUTH_URL=http://auth:4000` and `BLOB_URL=http://blob:3000`. Then check those names answer from inside the network:

    ```bash
    docker run --rm --network blob-storage curlimages/curl:8.10.1 -s -o /dev/null -w '%{http_code}\n' http://auth:4000/.well-known/jwks.json
    docker run --rm --network blob-storage curlimages/curl:8.10.1 -s -o /dev/null -w '%{http_code}\n' http://blob:3000/files
    ```

    `200` from auth and `401` from blob mean both are reachable.

5. Test the whole path, from the outside in:

    ```bash
    curl -s localhost:8080/health                                # gateway itself: {"status":"ok"}
    curl -s -X POST localhost:8080/api/auth/refresh              # gateway -> auth: {"error":"Not logged in"}
    curl -s -X POST localhost:5173/api/auth/refresh              # frontend -> gateway -> auth: same
    ```

    If the first two work and the third returns 500, the frontend can't reach the gateway: check that the gateway is on `blob-storage` (step 3) and that the frontend was built with `GATEWAY_URL=http://gateway:8080`.

## Fix

- **A stack isn't running**: start it, in order.

    ```bash
    (cd auth_service && docker compose up -d --build)
    (cd Blob_storage && docker compose up -d --build)
    (cd Blob_api_gateway && docker compose up -d --build)
    ```

- **A container isn't on `blob-storage`**: usually its stack was started before auth_service created the network, or the network was removed and recreated. Recreate that stack with `docker compose up -d --force-recreate` in its folder.
- **Wrong `AUTH_URL` or `BLOB_URL`**: fix `compose.yaml` in Blob_api_gateway (or the env you run it with), then `docker compose up -d` there.
- **The frontend can't reach the gateway**: `GATEWAY_URL` is baked in at build time, so rebuild: `cd Blob_frontend && docker compose up -d --build`.

Then rerun step 5.

## Prevent

- Start the stacks in order: auth → Blob_storage → gateway → frontend. See [Request flow](../architecture/request-flow.md).
- Keep the Grafana dashboard open when changing compose files or networks.
