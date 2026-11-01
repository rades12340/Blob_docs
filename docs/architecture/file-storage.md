# File storage

Blob_storage keeps everything in one S3 bucket: the file bytes and a small JSON record per file. There is no database. Listing, ownership and metadata all come from the S3 key layout.

Why there's no separate metadata store: see [ADR 0003](../decisions/0003-file-listing-in-blob-service.md). For the API, see the [Blob API reference](../api/blob.md).

## Key layout

Each upload is stored as two objects under its owner's prefix:

```text
<bucket>/
└── files/
    └── <owner>/              user id from the token's sub
        ├── <id>              the bytes, with Content-Type and Content-Disposition
        └── <id>.json         the record
```

| Part | Value |
| --- | --- |
| `<owner>` | The access token's `sub`, URL-encoded, with `.` also escaped as `%2E` so it can never read as `..` |
| `<id>` | A new UUID per upload |
| `<id>` object | The file. `Content-Type` is the uploaded type (or `application/octet-stream`). `Content-Disposition: attachment; filename*=UTF-8''<name>`, so downloads save under the original name. |
| `<id>.json` object | `{ id, ownerId, name, size, type, sha256, createdAt }`, the same shape the API returns |

`fileKey(owner, id)` in `src/storage.ts` builds the key. Every lookup goes through it with the owner from the token, so **the key layout is the ownership check**: a user can only ever read under their own prefix.

## Upload

`POST /upload` with a multipart `file` field:

1. Verify the access token. The owner is its `sub`.
2. Read the form. Missing or broken form: `400`.
3. File over `MAX_UPLOAD_BYTES` (25 MB): `413`.
4. Read the whole file into memory and compute its SHA-256.
5. `PUT files/<owner>/<id>` with the bytes.
6. `PUT files/<owner>/<id>.json` with the record. It's written **last**, so a record only exists once its bytes do.
7. Return the record.

If S3 fails at step 5 or 6, the response is `502 { error: "Storage unavailable" }`. A failure at step 6 can leave an orphaned `<id>` object without a record. It never shows up in listings.

The full hop-by-hop flow, including the size limits before Blob_storage, is in [Request flow](request-flow.md).

## Listing

`GET /files`:

1. List every key under `files/<owner>/`, following S3's continuation tokens so more than 1,000 objects work.
2. Keep the keys that end in `.json`.
3. Read each record.
4. Sort newest first by `createdAt` and return `{ files: [...] }`.

Listing costs one `ListObjectsV2` call per 1,000 keys plus one `GET` per file. That's fine at this scale. Lots of files per user would need a different index.

## Presigned downloads

`GET /download/:id`:

1. Reject an id that isn't a UUID (it's answered as `404`).
2. Read `files/<owner>/<id>.json`. Missing means `404`. Another user's file looks exactly the same, because it's under a different prefix.
3. Sign a `GET` URL for `files/<owner>/<id>`, valid for `DOWNLOAD_URL_TTL` seconds (default 300).
4. Return `{ url, expiresAt, name, size, type, sha256 }`.

Signing is done locally with the S3 credentials; it makes no request. The browser then downloads straight from S3, so file bytes never pass through the services on the way out. The server doesn't re-check the hash on download; a client can compare `sha256` with what it got.

The URL's signature is a credential until it expires. It's never logged, only that a link was issued (`download link issued`, with `fileId` and `expiresAt`).

### Two S3 addresses

The server and the browser may reach S3 at different addresses. In Docker, Blob_storage talks to S3Mock at `http://s3:9090` on the compose network, but your browser reaches it at `http://localhost:9090`. A link signed for `s3:9090` wouldn't work in the browser.

So Blob_storage uses two S3 clients: one for reads and writes (`S3_ENDPOINT`), and one only for signing (`S3_PUBLIC_ENDPOINT`). With AWS S3, both are the same and you set neither.

## S3Mock locally, AWS S3 in production

| | S3Mock (local) | AWS S3 |
| --- | --- | --- |
| How it runs | `adobe/s3mock:4.7.0` in Blob_storage's `compose.yaml`, bucket `blobs` created at start | A bucket you create, with **Block all public access** on |
| `S3_ENDPOINT` | `http://s3:9090` (Docker) or `http://localhost:9090` | Not set |
| `S3_PUBLIC_ENDPOINT` | `http://localhost:9090` (Docker only) | Not set |
| `S3_BUCKET` | `blobs` | Your bucket |
| `S3_REGION` | `us-east-1` | Your bucket's region |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | `test` / `test` (any value works) | An IAM user's access key. The `AWS_*` names also work. |
| Data survives a restart | No, only while the container runs | Yes |
| Checks signatures and expiry | No: an expired link still works | Yes |

The IAM policy only needs `s3:PutObject` and `s3:GetObject` on `files/*` and `s3:ListBucket` limited to the `files/` prefix. The exact policy and console steps are in [Blob_storage's README](https://github.com/rades12340/Blob_storage#s3-setup). Running it for real is covered in [Running on AWS](../operations/aws.md), and key rotation in [Rotate S3 keys](../runbooks/rotate-s3-keys.md).

## Settings

| Variable | Default | Purpose |
| --- | --- | --- |
| `S3_BUCKET` | required | The bucket. The server won't start without it. |
| `S3_REGION` | — | Bucket region. |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | required | Credentials. |
| `S3_ENDPOINT` | AWS | Only for an S3-compatible server such as S3Mock. |
| `S3_PUBLIC_ENDPOINT` | `S3_ENDPOINT` | Address download links are signed for. |
| `MAX_UPLOAD_BYTES` | `26214400` (25 MB) | Larger files get `413`. |
| `DOWNLOAD_URL_TTL` | `300` | Seconds a download link stays valid. |

If S3 is down or misconfigured, all three file routes return `502` and log `storage request failed` with the `operation` (`put`, `get` or `list`). See [S3 unreachable](../runbooks/s3-unreachable.md).
