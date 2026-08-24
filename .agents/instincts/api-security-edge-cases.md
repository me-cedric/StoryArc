---
id: api-security-edge-cases
trigger: 'when an API change touches authorization scope, encrypted tokens, provider tokens, uploads, cleanup jobs, or sensitive logging'
confidence: 0.9
domain: security
source: local-repo-analysis
---

# Check the security edges APIs usually miss

When an API touches identity, ownership, external provider tokens, uploads, or
background cleanup, review these edges before calling it safe.

## Scope every by-id path

For tenant, region, account, organization, or user-owned data:

- derive scope from the authenticated token/session, not the request body
- apply scope predicates to every by-id read, update, delete, and child-resource
  query, not just list endpoints
- fail closed when scope cannot be resolved
- return 404 or 403 consistently for out-of-scope resources
- prove it with a cross-scope regression test

Do not let a list endpoint enforce scope while `GET /resource/:id` bypasses it.
That is the common BOLA/IDOR hole.

## Never log bearer-like values

Device tokens, session ids, API keys, OAuth codes, reset tokens, signed URLs, and
provider request bodies stay out of logs and error responses. Use a stable
non-secret fingerprint instead:

```ts
import { createHash } from 'node:crypto';

export const fingerprint = (value: string) =>
  createHash('sha256').update(value).digest('hex').slice(0, 12);
```

Add tests that the raw value is absent and the fingerprint is present.

## Do not use ciphertext as a lookup key

If a secret must be encrypted at rest and deduplicated, random-IV authenticated
encryption and uniqueness need two columns:

- `secret_ciphertext`: versioned AES-GCM envelope, random IV, auth tag
- `secret_lookup`: deterministic HMAC-SHA256 with a separate key, unique index

Do not switch deterministic encryption directly to random-IV encryption without
adding the lookup column first, or duplicate detection breaks.

## Cleanup jobs need failure semantics

External provider lookup failure is not the same as "resource expired".
Background cleanup must distinguish:

- provider says resource/session/token is gone -> cleanup can delete
- provider is unavailable/unauthorized/timed out -> keep data, retry later

Never delete local rows because the provider was temporarily unreachable.

## Uploads and paths

Validate extension, MIME, size, and content limits at the boundary. Normalize
paths, reject traversal (`..`, absolute paths, encoded separators), and never
join user input directly into storage paths without a safe generated key.
