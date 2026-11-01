# 0008. One repo per service

## Status

Accepted, 2026-10-05.

## Context

The system has four services and an observability stack, each with its own language setup, Dockerfile and compose file. They could live in one monorepo or in separate repos.

## Decision

Each service has its own repo: auth_service, Blob_storage, Blob_api_gateway, Blob_frontend and Blob_observability. Each has its own CI, PR checks and releases. This docs repo ties them together.

## Consequences

Good:

- Independent CI and deploys. A broken test in one service doesn't block the others.
- Small blast radius for a bad change, and simple permissions.
- Each repo is small enough to read in one go.

Bad:

- A change across services needs several PRs, merged in the right order.
- Shared code is copied, like `src/log.ts` ([ADR 0006](0006-json-logs-and-request-ids.md)), and can drift.
- The big picture isn't in any one repo, so it has to be written down here.

## Alternatives considered

- **Monorepo with workspaces**: atomic cross-service changes and shared packages, but one CI for everything, and coupling that's easy to add and hard to remove.
