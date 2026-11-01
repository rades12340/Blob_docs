# Running on AWS

Locally, Blob_storage keeps files in S3Mock. This page moves it to a real S3 bucket, step by step, and shows how to check the result with the AWS CLI. Only Blob_storage talks to S3: no other service changes.

!!! warning "Never commit keys"
    Access keys go in `.env`, which is git-ignored, or in your secrets store. Never in `compose.yaml`, a README or a PR. If a key leaks, **delete it in IAM immediately**, then create a new one. See [Rotate S3 keys](../runbooks/rotate-s3-keys.md).

## 1. Account basics

1. Create an AWS account.
2. Turn on **MFA for the root user** (IAM → Security credentials → Assign MFA). After that, don't use the root user for daily work.
3. Set a **budget alert**: Billing and Cost Management → Budgets → Create budget → a monthly cost budget, for example $5, with an email alert. S3 for a few test files costs cents, but a leaked key can cost much more.

## 2. A personal login

Set up **IAM Identity Center** (search "IAM Identity Center" → Enable). Create a user for yourself and give it the `AdministratorAccess` permission set on the account. Sign in through the access portal URL it gives you, not as root.

For the CLI, use the same login:

```bash
aws configure sso          # once: portal URL, region, account, permission set; name the profile e.g. "admin"
aws sso login --profile admin
aws sts get-caller-identity --profile admin
```

## 3. The bucket

S3 → **Create bucket**:

- **Name:** globally unique, for example `blob-storage-<you>`.
- **Region:** the one closest to you, for example `eu-central-1`.
- **Block all public access:** leave it **on**. Files are only reachable through presigned links, which work on a private bucket.

Or with the CLI:

```bash
BUCKET=blob-storage-you
REGION=eu-central-1
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" --profile admin
aws s3api get-public-access-block --bucket "$BUCKET" --profile admin   # all four should be true
```

(In `us-east-1`, leave out `--create-bucket-configuration`.)

## 4. A service user with the least-privilege policy

The service gets its own IAM user with only what Blob_storage does: write and read objects under `files/`, and list that prefix. This is the policy from Blob_storage's README.

1. IAM → Users → **Create user**, for example `blob-storage-service`, without console access.
2. On the user, **Add permissions → Create inline policy**, JSON tab, and paste this with your bucket name instead of `<bucket>`:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": ["s3:PutObject", "s3:GetObject"],
          "Resource": "arn:aws:s3:::<bucket>/files/*"
        },
        {
          "Effect": "Allow",
          "Action": "s3:ListBucket",
          "Resource": "arn:aws:s3:::<bucket>",
          "Condition": { "StringLike": { "s3:prefix": "files/*" } }
        }
      ]
    }
    ```

3. On the user, **Security credentials → Create access key** → "Application running outside AWS". Copy the key id and secret now: the secret is shown only once.

| Statement | Why the service needs it |
| --- | --- |
| `s3:PutObject` on `files/*` | Upload writes the file and its `.json` record. |
| `s3:GetObject` on `files/*` | Reading records, checking they exist, and signing download links. A presigned URL only works if the signer may `GetObject`. |
| `s3:ListBucket` with `s3:prefix` `files/*` | `GET /files` lists the caller's `files/<user>/` prefix. |

No delete, no bucket settings, nothing outside `files/`.

!!! note "Later: a role instead of keys"
    When the service runs on AWS (ECS, EC2), attach the same policy to a task role or instance profile and drop the access key. Bun's S3 client then picks up temporary credentials. This is on the [security checklist](security.md).

## 5. Point Blob_storage at the bucket

Blob_storage's `compose.yaml` still hardcodes S3Mock (`S3_ENDPOINT`, `test`/`test`), so for now run the service with Bun instead of compose. In your Blob_storage checkout, create `.env`:

```bash
# .env (git-ignored)
S3_BUCKET=blob-storage-you
S3_REGION=eu-central-1
S3_ACCESS_KEY_ID=AKIA...
S3_SECRET_ACCESS_KEY=...
# No S3_ENDPOINT and no S3_PUBLIC_ENDPOINT: both default to AWS.
```

Then stop the compose stack (it holds port 3000) and start the service:

```bash
docker compose down          # in Blob_storage
bun install
bun run dev                  # http://localhost:3000, reads .env
```

auth_service must be on `localhost:4000` (its compose stack is fine): Blob_storage fetches the public keys from `http://localhost:4000/.well-known/jwks.json` by default.

Through the gateway, change `BLOB_URL` in Blob_api_gateway's compose file to `http://host.docker.internal:3000`, or run the gateway with Bun too (`bun run dev`, which defaults to `http://localhost:3000`). On Linux, `host.docker.internal` needs `extra_hosts: ["host.docker.internal:host-gateway"]` on the gateway service.

!!! note "Open item"
    Making the S3 settings in Blob_storage's `compose.yaml` overridable from `.env` would let the whole stack run against AWS without these workarounds.

## 6. Verify

Upload a file with the [curl walkthrough](../api/index.md#walkthrough-with-curl), then look in the bucket with your admin profile:

```bash
aws s3 ls "s3://$BUCKET/files/" --recursive --profile admin
```

Each upload is two objects: `files/<user id>/<file id>` (the bytes) and `files/<user id>/<file id>.json` (the record). The download link from `GET /api/blob/download/<id>` now starts with `https://<bucket>.s3.<region>.amazonaws.com/`.

Check the service user can't do more than it should:

```bash
aws configure --profile blob-service      # the service user's key, region of the bucket
aws s3 ls "s3://$BUCKET/files/" --profile blob-service          # allowed
aws s3 ls "s3://$BUCKET/" --profile blob-service                # AccessDenied: prefix isn't files/*
aws s3 rm "s3://$BUCKET/files/x" --profile blob-service         # AccessDenied: no delete
```

If uploads now fail with `502 Storage unavailable`, the blob log line `storage request failed` has the S3 error. See [S3 unreachable](../runbooks/s3-unreachable.md).

## The AWS CLI against S3Mock

The same CLI works against the local S3Mock, which is handy to see what Blob_storage wrote. Add a profile:

```ini
# ~/.aws/config
[profile s3mock]
region = us-east-1
endpoint_url = http://localhost:9090
```

```ini
# ~/.aws/credentials
[s3mock]
aws_access_key_id = test
aws_secret_access_key = test
```

```bash
aws --profile s3mock s3 ls s3://blobs/ --recursive
aws --profile s3mock s3 cp s3://blobs/files/<user id>/<file id>.json -
```

`endpoint_url` in a profile needs AWS CLI v2.13 / v1.29 or newer. S3Mock accepts any credentials and doesn't check signatures, so it can't tell you whether a policy or an expiring link works: test those against AWS.
