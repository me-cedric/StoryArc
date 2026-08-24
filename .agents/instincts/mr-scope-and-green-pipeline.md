---
id: mr-scope-and-green-pipeline
trigger: 'when reviewing an MR/PR whose pipeline is red, or whose diff bundles work beyond the ticket title'
confidence: 0.8
domain: delivery
source: local-repo-analysis
---

# Read the failing job, and watch what the MR quietly drags in

## Action

**A red pipeline is not automatically a code problem.** Open the failing *job*,
not just the pipeline status. `commitlint` runs over the **whole MR commit
range** — an inherited, non-conventional commit (a branch-name subject like
`Feature/cdm events apis`, no `type: subject`) reddens every build with
`subject-empty` / `type-empty`, even when `test`, `lint`, `typecheck`, and `e2e`
are all green. Fix = reword/squash that one commit (or squash-merge); don't hunt
the code.

**Scope-check the diff against the ticket.** A feature MR ("event list page")
that also carries auth/realm resolver changes, Keycloak realm config, or a
monorepo-wide gate change (e.g. dropping `--max-warnings 0` from `lint-staged`)
deserves an explicit callout:

- Authn/authz surface changes (which realm authenticates which routes) need
  sign-off from the backend/security owner, ideally in their own commit/ticket —
  even when well-commented and genuinely needed by the feature.
- Gate weakenings unrelated to the feature → flag to revert or isolate in a
  dedicated `chore:`.

## Why

Two real cases on one MR: the pipeline was red for days purely on an inherited
branch-name commit while all code jobs passed — "red" read as "broken code" and
hid that the feature was actually green. And the same MR silently broadened a
Keycloak realm resolver to accept a second realm's tokens on `/backoffice/*`
routes. Both are invisible if you review only the feature files and trust the
pipeline colour. Pairs with [[commit-convention]] and [[self-review-before-done]].
