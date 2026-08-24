---
id: spec-status-sync
trigger: 'when you implement, change, or audit a feature that has a spec-kit spec (specs/**/spec.md, tasks.md), or touch docs/spec-kit'
confidence: 0.9
domain: delivery
source: hand-authored
---

# Keep spec status in sync when you ship — verified, not labelled

## Action

When you ship (or change the completion state of) anything a spec-kit spec
covers, update the status **in the same task** — never leave it for "later":

1. **Global source of truth** — `docs/spec-kit/implementation-status.md` (the
   maintained per-domain table). Update the row + evidence.
2. **The spec's own `## Implementation Status`** — a *hybrid*: a one-line
   verified status (`Implemented` / `Implemented (backend)` / `Partial` /
   `Out of scope` / `Not implemented`) + the concrete modules/endpoints, then a
   pointer to the global doc for detail. Never leave the generated placeholder
   `Not implemented (SFD status: draft)` on a feature that has shipped.
3. **`tasks.md`** — append the dated task entry (the repo convention: a `C<id>`
   narrative bullet + a `Verification:` line) and tick any `checklist.md`.

**Verify against wired code, not labels or trackers.** A schema-only table with
no controller is NOT "implemented"; a module with a controller + tests is. Even
a "maintained" status doc drifts in its prose — cross-check the module tree.
Separate **backend** from **frontend**, and distinguish **gated** (blocked on a
credential/decision) from **unbuilt**. Do not blind-flip specs to a generic
"implemented" — several are genuinely partial or gated.

## Why

Spec status drifts the moment code lands but the doc doesn't. Left unattended it
rots to the point where most specs read "Not implemented" while the features are
live — so nobody trusts the spec set to plan against, and every audit re-derives
reality from scratch. Syncing status in the same task — verified against code,
with each spec pointing at one source of truth — is the cheap discipline that
keeps the spec set honest. Same principle as [[verified-progress-signal]] (trust
wired code over the reported number) and [[self-review-before-done]] (finish the
loop before calling it done), applied to the spec artifacts.
