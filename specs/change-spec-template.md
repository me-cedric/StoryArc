# Change — <name>

| Field | Value |
| --- | --- |
| Slug | `<id-slug>` |
| Status | Draft / Ready / Done |
| Type | UI / API / data / infrastructure |
| Visual source | Figma node, `DESIGN.md`, or none |

> Save this file as `specs/changes/<id-slug>.md`. The slug in the path is the one
> passed to `--change`.
>
> **Two headings below are a machine contract.** `agent-compass evidence
> --phase finish` reads the bullet lists under `## Acceptance criteria` and
> `## Expected proof scenarios` literally, and copies them into the change
> report. Rename them and the report comes back empty.

## Objective

What this change is for, in two or three sentences. The user-visible outcome,
not the implementation.

## Experience

What the user does and sees, including the small screen. Name the states that
matter: loading, empty, error, partial data.

## Acceptance criteria

Give every criterion a stable id. The id is what a test, a review and the report
all point at, so it must not change once work starts.

- `AB-01` — <one testable statement>
- `AB-02` — <one testable statement>

## Design rules

- Reuse the existing components and tokens. Name them.
- State any extension the change needs, before writing it.
- Say what must not be created: a second button, a one-off token, a local copy
  of a shared component.

## Accessibility

The rules this change must hold, from the compass accessibility guideline. Name
the keyboard path, the accessible names, and the focus behaviour after the
interaction.

## Expected proof scenarios

What the evidence must show. One line per scenario, at the level a reviewer can
check.

- <nominal path, desktop and mobile>
- <the sensitive state: error, empty, or the interaction that changed>
- <the non-regression this change could plausibly break>

## Expected screenshots

Name the files after the screen and the state, so a missing one is obvious in
the report.

- `desktop/<name>.png`
- `mobile/<name>.png`

## Out of scope

List what this change deliberately does not do. A reviewer reads this before
asking for more.

## Commands

```bash
agent-compass evidence --change <id-slug> --phase start --run
# implement, with the targeted tests
agent-compass evidence --change <id-slug> --phase finish --run
```

The report lands at `.agent/changes/<id-slug>/index.html` and must read
`CHANGE CONFORM`. A conform report still needs the human review of the visual
comparison.
