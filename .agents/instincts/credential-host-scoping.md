---
id: credential-host-scoping
trigger: 'when code resolves a stored secret from a URL — a git credential helper, a registry token, a per-tenant API key, an outbound webhook signature'
confidence: 0.9
domain: security
source: local-repo-analysis
---

# Bind a secret to its host, and parse that host once

A stored secret belongs to one destination host. Resolve the host from the URL
you are about to call, and look the secret up under that host. A crafted URL that
hides a second host must never receive the first host's token.

## Parse the authority exactly

Two cuts decide the host, and both are easy to get wrong:

- Cut the scheme at the **first** `://`. A second scheme inside a path or a query
  must not choose the host. `https://good.example/go?to=https://evil.example`
  resolves `good.example`.
- End the authority at the first `/`, `?` **or** `#`. A cut at `/` alone lets
  `https://good.example/?x=@evil.example` and `https://good.example#@evil.example`
  resolve `evil.example`, because the userinfo rule then reads past the query.

Then strip userinfo and port: take the segment after the last `@`, and the part
before the first `:`.

## Fail closed on a host you cannot validate

Accept a narrow character set — letters, digits, `-` and `.` — and reject
everything else. Return no host rather than a doubtful one. No host must disable
every credential source, because a secret cannot be attributed to a host you
could not read.

```rust
// A crafted URL keeps the real host, or it resolves nothing. Never the attacker.
for hostile in [
    "https://good.example/?redirect=@evil.example",
    "https://good.example#@evil.example",
    "https://good.example/redirect?to=https://evil.example",
] {
    assert_eq!(host_of(hostile), "good.example");
}
```

## One parser for the whole application

This rule is subtle, so a second copy of it drifts. Export one function and make
every caller use it — the credential lookup, the API client, the push check, the
URL splitter that also needs the path. A duplicate that cut at `/` alone is how
the bug above reached production.

## Report the source, never the secret

A diagnostic view says which source answered for a host. It never carries the
token. Keep the secret inside the backend that resolved it.

## Test the crafted shapes, not only the happy path

Add one test per hidden-host shape: query, fragment, second scheme, userinfo.
Add one test that a malformed host resolves nothing. Assert on the resolved host,
so the test fails before any request goes out.
