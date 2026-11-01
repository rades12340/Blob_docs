# Request flow

!!! note "To be written"
    Sequence diagram of one upload: browser → Next.js /api rewrite → gateway (rate limit, request id, X-Forwarded-For) → blob_storage (JWT check against auth's JWKS) → S3. Why the browser only talks to its own origin. Body size limits at each hop.
