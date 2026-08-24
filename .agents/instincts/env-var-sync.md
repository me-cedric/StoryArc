---
id: env-var-sync
trigger: 'when adding, renaming, or removing an environment variable an app reads (config, secrets, feature flags, timeouts, provider selection)'
confidence: 0.95
domain: configuration
source: local-repo-analysis
---

# Keep env validation, examples, and local defaults in sync

An environment variable has three surfaces that must change together, in the
same task/PR. A var present in code but missing from any surface is a review
finding.

## 1. Validation schema

Declare every var the app reads in the central validation schema. Use precise
types: URLs as URLs, numbers as positive integers when required, booleans as an
explicit true/false shape, fixed sets as enums.

Optional by default. Make a var required only when the app cannot run without it
and there is no in-code fallback. For "required in production, skippable in
dev/test", enforce it with a production-gated validation branch instead of
making local development fail.

Add or update the validation test: one complete valid production fixture, plus a
"missing/invalid var throws" case for newly required vars.

Gotcha: some config loaders validate but still return raw strings. Coerce
numeric/boolean values at read time with a shared helper; do not assume schema
coercion changed what the runtime config service returns.

## 2. Example env file

Add the var to `.env.example` with a safe placeholder or safe default, plus a
one-line comment. Never use a real secret. Every validated var appears once.

## 3. Local dev env file

Add a working local default to the project's committed development env template
when it has one (`.env.development`, `.env.local.example`, or equivalent).
Prefer mock/offline providers, blank keys, and localhost URLs. Never commit
production secrets.

## Reading env correctly

Read through the typed/config service outside config bootstrap code. Avoid
direct `process.env` reads in feature code so validation stays the choke point.

## Housekeeping

Removing a feature removes its env vars from all three surfaces. If env files
need a full rewrite or de-duplication, make that a dedicated change.
