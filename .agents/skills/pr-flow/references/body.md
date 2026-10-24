# PR and MR body

The body is evidence, not prose. Start from the project template when it has one:
`.github/PULL_REQUEST_TEMPLATE.md` or `.gitlab/merge_request_templates/default.md`.

## Three rules

1. No fabrication. Write a section only when its evidence exists. Omit a check that did not run. Never guess a count, a verdict or a file name.
2. No duplication. State each fact once. Do not repeat what the labels, the diff or the changelog already say.
3. One language for the title, the prose and the section names: the language of the project's requests.

No attribution line: no `Co-Authored-By`, no "Generated with".

## Always present

1. An opening paragraph with no heading: who reported the problem or which work drives it, where it was found, the scope in one sentence.
   Say what the change deliberately does not touch only when such an item was considered and set aside.
2. The gate result:
   - one bold line when one package ran one gate type: `**Gate green: [N] suites, [N] tests.** Typecheck green, lint green.`
   - a `## Verification` table when more than one package or gate type ran: one row for each package and gate, with the exact counts.
   Give a baseline only when that earlier result was captured. Never repeat the current count as the baseline.
3. The delivered items, in one of two forms:
   - Form A: one `## <TICKET> — <the symptom a user saw>` section for each ticket, with `### Cause`.
   - Form B: one `## Delivered items` table (`Ticket`, `Item`) when there are more than 6 items, or when an item has no ticket.
     Say above it that an empty ticket cell means the search found none.

## Conditional sections

A section whose condition is false is deleted. Never leave it empty. Never write "N/A".

| Section | Condition |
|---|---|
| `### No widened access` | The change touches a guard, a permission or a scope. List each fact that you checked. |
| `### <N> regression cases pin <what>` | A test pins the fix. One line for each case: the input and the expected result. |
| `### Delivered scope: <label>` | The ticket is not delivered in full. Name the delivered slice. |
| `### Deliberately absent` | Part of the ask is missing on purpose. One row for each part, with the blocking decision or ticket. |
| `## Contract sync` | An API changed: the OpenAPI, the HTTP collection and the feature files that changed with it. |
| `## Drift fixed in passing` | The change makes a document or comment false. Name each one and the wrong line. |
| `## Manual test plan` | A person can see the change and tests do not cover it all. A checkbox list: one action and its expected result. |
| `## Know before merging` | A visible behavior change (for the release notes), a migration (number, additive or not, backfill), or a broken consumer. |
| `## Points to arbitrate` | An open decision blocks follow-up work but not this merge. Name each decision and what it blocks. |

## Scale

| Size | Required |
|---|---|
| One ticket, short fix | Opening, gate result, one Form A section, and the conditional sections that apply |
| 2 to 6 tickets | Opening, gate result, one Form A section for each ticket, `Verification` when more than one gate ran |
| More than 6 items, or an item without a ticket | Opening, gate result, Form B, and the conditional sections that apply |
