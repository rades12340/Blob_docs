# S3 unreachable

## Symptoms

- Upload, list or download calls fail with `502` and `{"error":"Storage unavailable"}`.
- Blob logs error `storage request failed`, with `operation` set to `put`, `get` or `list` and the S3 error in `error`.
- Sign-in still works. Only file operations fail.

If the body is `{"error":"Upstream unavailable"}` instead, the gateway can't reach the blob service at all: see [Gateway returns 502](gateway-502.md).

!!! tip "See it in Grafana"
    The **Warnings and errors** panel shows `blob / storage request failed`. In Explore:

    ```logql
    {container="blob"} | json | message="storage request failed"
    ```

    The `error` field usually names the cause: connection refused, `AccessDenied`, `InvalidAccessKeyId`, `NoSuchBucket`.

## Check

1. Read the latest errors:

    ```bash
    docker compose -p blob-service logs --no-log-prefix blob | grep 'storage request failed' | tail -5
    ```

2. Which S3 is the service using?

    ```bash
    docker inspect blob-service-blob-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^S3_' | grep -v SECRET
    ```

    `S3_ENDPOINT=http://s3:9090` means local S3Mock (go to step 3). No `S3_ENDPOINT` means AWS (go to step 4).

3. **Local S3Mock**: is it running, and does the bucket exist?

    ```bash
    docker compose -p blob-service ps
    curl -s -o /dev/null -w '%{http_code}\n' localhost:9090/blobs
    ```

    The `s3` service should be `running`, and the bucket should answer `200`.

4. **AWS**: do the same credentials work outside the service? Use the values from step 2 and the secret from wherever you set it:

    ```bash
    AWS_ACCESS_KEY_ID=<S3_ACCESS_KEY_ID> AWS_SECRET_ACCESS_KEY=<S3_SECRET_ACCESS_KEY> \
      aws s3 ls "s3://<S3_BUCKET>/files/" --region <S3_REGION>
    ```

    - `InvalidAccessKeyId` or `SignatureDoesNotMatch`: the key was deleted, deactivated or mistyped.
    - `AccessDenied`: the IAM policy doesn't allow `s3:ListBucket` on `files/*`, or `s3:GetObject`/`s3:PutObject` on `files/*`.
    - `NoSuchBucket` or a redirect: wrong `S3_BUCKET` or `S3_REGION`.
    - A timeout: the host can't reach AWS (network, proxy, DNS).

## Fix

- **S3Mock stopped**: `cd Blob_storage && docker compose up -d`. S3Mock keeps files only while its container exists, so files uploaded before it was removed are gone. Their records went with them, so the list is just empty.
- **Bad or rotated key**: put a working key in the service's environment and restart it. See [Rotate S3 access keys](rotate-s3-keys.md).
- **Wrong bucket or region**: fix `S3_BUCKET` / `S3_REGION` and restart.
- **Policy missing a permission**: fix the IAM user's inline policy. The policy is in the Blob_storage README under "S3 setup" and in [AWS](../operations/aws.md).

The service reads its S3 settings only at startup, so any change needs a restart.

Note: `compose.yaml` in Blob_storage hardcodes S3Mock (`S3_ENDPOINT`, keys `test`/`test`). To run the container against AWS you need your own override that sets `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` and leaves out `S3_ENDPOINT` and `S3_PUBLIC_ENDPOINT`.

## Prevent

- Don't delete or deactivate an access key until the service runs on its replacement.
- Keep the IAM policy and the code's S3 operations in sync: a new operation needs a policy change first.
