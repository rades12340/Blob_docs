# 0007. Loki and Grafana instead of ELK

## Status

Accepted, 2026-10-30.

## Context

With JSON logs in every service ([ADR 0006](0006-json-logs-and-request-ids.md)), we need one place to search them and a dashboard for the common failures. It should run on a laptop next to the rest of the stack.

## Decision

Blob_observability runs:

- **Alloy**: reads the containers' logs from Docker and labels each stream with `project` and `container` (the compose service: `auth`, `blob`, `gateway`, `frontend`).
- **Loki**: stores them for 7 days. Port `127.0.0.1:3100`.
- **Grafana** on port 3001, with the "Blob storage system" dashboard provisioned.

See [Observability](../operations/observability.md).

## Consequences

Good:

- Loki indexes only labels, so it runs in a few hundred MB of RAM.
- LogQL filters JSON fields, e.g. `{container="gateway"} | json | message="upstream request failed"`.
- The same Grafana can later show traces (Tempo) and metrics.

Bad:

- Full-text search over large volumes is slow, because log content isn't indexed.
- The local setup has no login (anonymous admin). Never expose port 3001.

## Alternatives considered

- **ELK (Elasticsearch, Logstash, Kibana)**: Elasticsearch needs 2–4 GB of RAM and tuning. It's the right choice for heavy full-text search at scale, which we don't have.
- **`docker compose logs` and `jq` only**: fine for one service, no view across services and no dashboard.
