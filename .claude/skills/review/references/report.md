# Review report

Write the report in the review language that the repository declares. Without one, use the language of the user.
Write for a reader who joined the project last week.

## Shape

```
## Verdict — <PR/MR> #<id> · <TICKET-123, or "no ticket"> · <source> → <target>
Scope: <n> files · <axes checked>
Evidence: <n> criteria verified · <n> code matches · <n> not verified (<reason>)
Blockers: <n> P0 · <n> P1
```

Then, in this order. A section with nothing in it is one line, never a table of "not applicable" rows.

1. Criteria: one row for each criterion, with its verdict and evidence.
2. Findings, most severe first, then the `Process` block.
3. Contracts and docs, tests, compatibility with the other open requests, validation.
4. What is good, named precisely.
5. The correction plan.

## Findings

- `P0` blocks the merge. `P1` must be fixed before the merge. `P2` should be fixed. `P3` is a nit.
- Each finding: `path:line`, what is wrong, why it matters in this repository, the fix. 2 to 4 sentences.
- A finding outside the changed lines gets a tag:
  - `[pre-existing]`: it was broken before, and this change does not make it worse. `P3`, or drop it.
  - `[revealed by this change]`: the line did not change, but this change makes it harmful. Rank it on its real severity.
- The `Process` block holds the findings with no line: an empty description, no label, a wrong commit type, no ticket, a wrong target branch.

## Correction plan

This section is mandatory. A review without it is not done.

- Two groups: "fix before merge" and "follow-up (ticket)".
- Each item: the files, the change in one sentence, a snippet when it is shorter than about 15 lines, and an effort `S`, `M` or `L`.
- Name the follow-up artifacts: the test file, the contract file, the ticket to open.
- Offer to apply it. Apply nothing and push nothing before the user says yes.

## Comments

- One inline comment for each finding on a changed line. Give the fix, not only the problem.
- A comment that an earlier thread already holds is a duplicate. Do not post it again.
- The tracker comment format can differ from Markdown (Jira uses wiki markup). Check before you post there.
