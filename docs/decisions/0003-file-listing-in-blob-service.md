# 0003. File listing lives in the blob service

## Status

Accepted, 2026-10-10.

## Context

Users need to see the files they uploaded. One suggestion was to keep that list in todos_service, which already stores per-user records. But Blob_storage already writes every file under its owner's prefix in S3 (`files/<owner>/<id>`), next to a small JSON record of its metadata (`files/<owner>/<id>.json`).

## Decision

`GET /files` in Blob_storage lists the caller's prefix in S3 and reads each record. todos_service is not used for files.

## Consequences

Good:

- Blob owns its data. There's no second store to keep in sync, and no failure where the list and the bucket disagree.
- Looking up under the caller's prefix is also the ownership check.
- No new dependency between services.

Bad:

- Listing reads every record of the user (two S3 requests per file, after paging through the prefix). That's fine at this scale.
- No sorting, search or paging on the server beyond newest-first.

Revisit with a database index if users have thousands of files.

## Alternatives considered

- **todos_service as the file index**: a second write per upload, a consistency problem when one write fails, and a coupling between unrelated services.
- **A database in Blob_storage now**: the right fix later, but a new piece of infrastructure we don't need yet.
