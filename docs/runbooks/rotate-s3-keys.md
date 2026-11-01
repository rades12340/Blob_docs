# Rotate S3 access keys

On AWS, Blob_storage reaches S3 with the access key of a dedicated IAM user: `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY` (the `AWS_*` names also work). It reads them **once at startup**, so a new key needs a restart. Locally, S3Mock accepts any key (`test`/`test`), so there's nothing to rotate.

**What users notice**: the blob service is down for the few seconds it takes to restart. Calls during that time get `502 {"error":"Upstream unavailable"}` from the gateway, and an upload in progress fails. Download links already handed out are signed with the old key. They stop working when that key is deactivated, so wait for them to expire first (`DOWNLOAD_URL_TTL`, default 300 seconds). Nobody is signed out.

## Symptoms

Use this runbook when:

- an access key may have leaked: **delete it in IAM first**, then follow the steps;
- someone who had the key leaves; or
- it's a scheduled rotation, or AWS flags the key as old.

!!! tip "See it in Grafana"
    If the service is still using a key you've deactivated, its S3 calls fail:

    ```logql
    {container="blob"} | json | message="storage request failed"
    ```

    It should stay at zero during and after the rotation. The **Warnings and errors** panel shows the same.

## Check

1. Find the IAM user and its keys. An IAM user can have at most two access keys, so you need a free slot:

    ```bash
    aws iam list-access-keys --user-name <blob-user>
    ```

    If there are already two, delete the one that isn't in use (check with `aws iam get-access-key-last-used --access-key-id <id>`).

2. Find where the service gets its keys. Running with `bun src/app.ts`, Bun loads them from `.env` in the Blob_storage folder. In Docker, it's the environment in your compose override: Blob_storage's own `compose.yaml` hardcodes S3Mock and can't point at AWS as it is.

## Fix

**A leaked key**: don't wait for a replacement. Delete it at once. The service returns `502 {"error":"Storage unavailable"}` until step 3 below is done.

```bash
aws iam delete-access-key --user-name <blob-user> --access-key-id <leaked-key-id>
```

Then check CloudTrail for what the key did. The IAM policy only allows `s3:PutObject` and `s3:GetObject` on `files/*` and `s3:ListBucket` for that prefix, so the exposure is the files in the bucket.

**A planned rotation**, and the rest of a leak response:

1. Create a second access key. Save the `AccessKeyId` and `SecretAccessKey` from the output; the secret is shown only once.

    ```bash
    aws iam create-access-key --user-name <blob-user>
    ```

2. Put the new values in the service's environment (`.env` or your compose override):

    ```bash
    S3_ACCESS_KEY_ID=AKIA...
    S3_SECRET_ACCESS_KEY=...
    ```

3. Restart the service so it reads them: stop and start `bun src/app.ts`, or in Docker:

    ```bash
    docker compose up -d --force-recreate blob
    ```

4. Check it works. Upload, list and download a file in the app, and check the log has no new errors:

    ```bash
    docker compose logs --no-log-prefix blob | grep -c 'storage request failed'
    ```

5. Wait at least `DOWNLOAD_URL_TTL` (300 seconds by default), so download links signed with the old key expire.

6. Deactivate the old key. Wait a while (an hour or a day) and watch for errors. Anything still using the key breaks now, while it can still be turned back on:

    ```bash
    aws iam update-access-key --user-name <blob-user> --access-key-id <old-key-id> --status Inactive
    ```

7. Delete it:

    ```bash
    aws iam delete-access-key --user-name <blob-user> --access-key-id <old-key-id>
    ```

## Prevent

- Keep keys out of Git and images: `.env` is in `.gitignore` and `.dockerignore`.
- Give the IAM user only the policy in [AWS](../operations/aws.md), so a leaked key can't do more than the service can.
- Rotate on a schedule, so the procedure is practised before a leak forces it.
