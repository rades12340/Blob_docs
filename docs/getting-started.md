# Getting started

This page gets the whole system running on your machine. There are two ways:

- [With Docker](#run-everything-with-docker): one compose stack per repo. Closest to production. Start here.
- [Without Docker](#run-without-docker): `bun run dev` in each repo, for fast reloads while you change code.

## Prerequisites

| Tool | Version | Why |
| --- | --- | --- |
| Git | any | Clone the repos. |
| Docker with Compose | Compose v2 (`docker compose`) | Runs the stacks and S3Mock. |
| [Bun](https://bun.com) | 1.3 or newer | Generates auth_service's signing key. Also runs the services without Docker. |
| `curl` and `jq` | any | Optional, for the API checks below. |

These ports must be free: 3000, 3001, 3100, 4000, 5173, 8080, 9090, 12345.

## Clone the repos

Put all five repos side by side in one folder. The compose files and READMEs assume they are siblings.

```bash
mkdir blob && cd blob
for repo in auth_service Blob_storage Blob_api_gateway Blob_frontend Blob_observability; do
  git clone https://github.com/rades12340/$repo.git
done
```

## Run everything with Docker

### 1. Create auth_service's signing key

auth_service signs access tokens with a private Ed25519 key, read from `AUTH_PRIVATE_KEY` in its `.env`. Its `compose.yaml` sets every other variable itself.

```bash
cd auth_service
bun install
cp .env.example .env
bun run gen-key >> .env   # appends AUTH_PRIVATE_KEY='{...}'
cd ..
```

Do this once. `.env` is ignored by git; keep the key out of commits and chat. The other stacks need no `.env`.

### 2. Start the stacks in order

auth_service's stack creates the shared Docker network `blob-storage`. Every other stack joins it as an external network and reaches the others by service name (`auth`, `blob`, `gateway`). So start auth_service first:

```bash
(cd auth_service       && docker compose up -d --build)   # :4000, creates the blob-storage network
(cd Blob_storage       && docker compose up -d --build)   # :3000, plus S3Mock on :9090
(cd Blob_api_gateway   && docker compose up -d --build)   # :8080
(cd Blob_frontend      && docker compose up -d --build)   # :5173
(cd Blob_observability && docker compose up -d)           # Grafana on :3001
```

Blob_observability can start at any point after the network exists. It picks up containers as they come and go.

If a later stack fails with `network blob-storage declared as external, but could not be found`, auth_service's stack isn't up. Start it first.

Check that everything is up:

```bash
docker compose ls   # expect auth-service, blob-service, api-gateway, blob-frontend, blob-observability
curl -s localhost:8080/health   # {"status":"ok"}
```

### 3. Sign up and upload a file

Open **<http://localhost:5173>**, create an account, then upload a file and download it again.

Or do the same from the command line, through the gateway:

```bash
curl -X POST localhost:8080/api/auth/register -H 'content-type: application/json' \
  -d '{"email":"me@example.com","password":"password123"}'

TOKEN=$(curl -s -X POST localhost:8080/api/auth/login -H 'content-type: application/json' \
  -d '{"email":"me@example.com","password":"password123"}' | jq -r .accessToken)

echo "hello" > hello.txt
ID=$(curl -s -H "Authorization: Bearer $TOKEN" -F file=@hello.txt localhost:8080/api/blob/upload | jq -r .id)
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/blob/files | jq

URL=$(curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/blob/download/$ID | jq -r .url)
curl -s "$URL"   # hello
```

The download link points at `localhost:9090` (S3Mock) and expires after 300 seconds. Passwords must be 8 to 256 characters.

### 4. Look at the logs

Open **<http://localhost:3001>**. The **Blob storage system** dashboard is the home page, with no login. Every API response has an `X-Request-Id` header. Paste one into the **Request id** box at the top to see that request in every service.

To read one stack's logs without Grafana:

```bash
(cd Blob_api_gateway && docker compose logs -f)
```

See [Logging and request ids](architecture/logging.md) and [Observability](operations/observability.md).

### 5. Change code

Rebuild the stack of the repo you changed:

```bash
(cd Blob_storage && docker compose up -d --build)
```

Blob_frontend reads `GATEWAY_URL` and `NEXT_PUBLIC_MAX_UPLOAD_BYTES` at build time, so changing either one also needs a rebuild.

### 6. Stop everything

```bash
for d in Blob_observability Blob_frontend Blob_api_gateway Blob_storage auth_service; do
  (cd $d && docker compose down)
done
```

Stop auth_service last: its stack owns the `blob-storage` network, and Docker won't remove a network that containers still use.

What survives a restart:

| Data | Where | Survives `down`? | Delete with |
| --- | --- | --- | --- |
| Users and refresh tokens | `auth-data` volume (SQLite) | Yes | `docker compose down -v` in auth_service |
| Uploaded files | S3Mock container | No: S3Mock keeps files only while it runs | — |
| Logs in Loki (7 days) | `loki-data` volume | Yes | `docker compose down -v` in Blob_observability |

## Run without Docker

Use this when you're changing a service and want `--watch` reloads. Every repo has a `bun run dev` script. You still need an S3 server: S3Mock in Docker is the easiest.

| Repo | Command | Listens on | Needs |
| --- | --- | --- | --- |
| S3Mock | `docker run` (below) | 9090 | Docker |
| auth_service | `bun run dev` | 4000 | `.env` with `AUTH_PRIVATE_KEY` |
| Blob_storage | `bun run dev` | 3000 | `.env` with the `S3_*` variables |
| Blob_api_gateway | `bun run dev` | 8080 | auth on 4000, blob on 3000 |
| Blob_frontend | `bun run dev` | 5173 | gateway on 8080 |

The defaults in every repo already point at these localhost ports, so the services find each other without extra settings.

Stop the Docker stacks first, or the ports will clash. Use one terminal per service.

### 1. S3Mock

```bash
docker run --rm -p 9090:9090 -e COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS=blobs adobe/s3mock:4.7.0
```

### 2. auth_service

```bash
cd auth_service
bun install
cp .env.example .env            # skip if you made it for Docker
bun run gen-key >> .env         # skip if .env already has AUTH_PRIVATE_KEY
```

Edit `.env` and set:

```bash
COOKIE_SECURE=false   # plain http locally, so the refresh cookie can't require https
TRUST_PROXY=true      # requests arrive through the gateway
```

Then:

```bash
bun run dev   # http://localhost:4000
```

### 3. Blob_storage

```bash
cd Blob_storage
bun install
cat > .env <<'EOF'
S3_ENDPOINT=http://localhost:9090
S3_BUCKET=blobs
S3_REGION=us-east-1
S3_ACCESS_KEY_ID=test
S3_SECRET_ACCESS_KEY=test
EOF
bun run dev   # http://localhost:3000
```

The server won't start without `S3_BUCKET`. Its port is fixed at 3000: there is no `PORT` variable.

### 4. Blob_api_gateway

```bash
cd Blob_api_gateway
bun install
TRUST_PROXY=true bun run dev   # http://localhost:8080
```

`TRUST_PROXY=true` makes the gateway rate limit by the browser's address, which Blob_frontend's server forwards in `X-Forwarded-For`. Without it every browser shares one limit. See [ADR 0005](decisions/0005-trust-proxy.md).

### 5. Blob_frontend

```bash
cd Blob_frontend
bun install
bun run dev   # http://localhost:5173
```

Open <http://localhost:5173> and sign up. The [curl checks](#3-sign-up-and-upload-a-file) above work unchanged against `localhost:8080`.

To collect these logs in Grafana you need Docker: Blob_observability only reads logs from Docker containers. Without it, read each terminal, which prints one JSON object per line.

## Next steps

- [Request flow](architecture/request-flow.md): what happens between the browser and S3.
- [Using the API](api/index.md): the endpoints and how to call them.
- [Runbooks](runbooks/index.md): what to do when it breaks, for example [Gateway returns 502](runbooks/gateway-502.md).
