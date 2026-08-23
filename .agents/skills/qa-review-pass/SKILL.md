---
name: qa-review-pass
description: >
  Run an end-to-end QA review pass and write the tester report — every
  requirement scenario given a verdict, every screen compared against its design
  reference, every finding split into a defect or a change request. Use when a QA
  tester, a Product Owner or a project manager asks whether the build matches the
  specification, asks for a QA report, an acceptance review, a test coverage
  matrix, or a defect list before a release.
risk_level: low
writes_files: true
requires_tools: [git, playwright]
license: MIT
metadata:
  version: "1"
---

# QA review pass

Answer one question for the team: **does the build match what we said we would
build, and what it was supposed to look like?**

The reviewer is not the author of the code. The output is a report, not a fix.
Its siblings are `impact-analysis`, which tells a developer what else to change,
and `delivery-digest`, which tells a Product Owner what shipped. Never mix the
three audiences in one file.

## Paths

This skill uses the tokens below. Replace each token with the host path. When the
host project puts an artifact somewhere else, use the host path and say so in the
report.

| Token | Holds | Default path |
| --- | --- | --- |
| `{{OPENSPEC_DIR}}` | specifications and requirements | `specs/` |
| `{{ADR_DIR}}` | decision records | `docs/decisions/` |
| `{{DELIVERY_DIR}}` | delivery outputs | `docs/delivery/` |
| `{{DESIGNS_DIR}}` | mockups and HTML prototypes | `docs/designs/` |
| `{{DESIGN_MD}}` | design system and tokens | `design.md` |
| `{{DATE}}` | the date of the pass, `YYYY-MM-DD` | — |

## The three sources of truth

Review against all three. A pass that checks only one of them is not a QA pass.

1. **Behaviour** — the specifications under `{{OPENSPEC_DIR}}`. Every
   `### Requirement:` with its `#### Scenario:` GIVEN/WHEN/THEN blocks is a test
   case. That mapping is the backbone of the pass.
2. **Look** — the design document `{{DESIGN_MD}}`, the design token file the
   project holds, the mockups and HTML prototypes under `{{DESIGNS_DIR}}`, and
   any Figma frame the project names. A generated HTML preview counts as a
   reference.
3. **Contract** — the API contracts, the data models, and the decision records
   under `{{ADR_DIR}}`, where the change touches them.

## The pass

1. **Fix the scope.** Name the change set, the base git reference, and the
   requirements in scope. Ask the user when any of the three is missing. A pass
   with no stated scope produces a report nobody can act on.
2. **Extract the test cases.** Read every requirement in scope. Turn each
   scenario into one row of the coverage matrix. Keep the requirement title and
   the scenario title exactly as the specification writes them.
3. **Collect the references.** List the screens in scope. Pair each screen with
   its mockup, prototype or Figma frame. Record `no reference` when a screen has
   none. That is a finding about the design set.
4. **Run the automated evidence.** Run the project unit test command, then the
   end-to-end suite, then the visual checks. Name the exact command. Record the
   exact result. Write `not run` plus the reason when a command fails to start.
   Never guess a result.
5. **Compare the screens.** Use the companion skill
   `visual-regression-playwright` for the capture, the diff and the thresholds.
   Do not restate its mechanics here. Record one row per screen.
6. **Walk the accessibility floor.** Check keyboard reachability, focus order, a
   visible focus ring, an accessible name on every control, colour contrast, and
   reduced motion. Report each check as pass or fail with the control that
   failed.
7. **Split defects from change requests.** A **defect** breaks what the
   specification already says. A **change request** shows that the specification
   is wrong or absent. File the second as the first and the team argues about
   blame instead of scope.
8. **List what you could not verify.** Name each unverified item. Name what you
   need to verify it: a credential, a fixture, a device, a decision, or an
   environment.

## Verdicts

Use these five words only. One verdict per scenario.

| Verdict | Meaning | Default action |
| --- | --- | --- |
| `pass` | You observed the scenario, and it behaves as specified | none |
| `fail` | You observed the scenario, and it breaks the specification | raise a defect |
| `partial` | Part of the scenario holds, part breaks | raise a defect for the broken part |
| `blocked` | You could not run the scenario | list the blocker in `Not verified` |
| `not-covered` | No automated test exercises this scenario | raise a test gap |

`not-covered` is a finding about the test suite, not about the feature. Never
report it as `pass`.

## Severity

| Level | Rule |
| --- | --- |
| P0 | Data loss, a security breach, or a broken primary flow. Stop the release. |
| P1 | A specified behaviour breaks, and no workaround exists. Fix before release. |
| P2 | A specified behaviour breaks, and a workaround exists. Fix in the next sprint. |
| P3 | Cosmetic drift, wording, or a minor gap. Put it in the backlog. |

## Output

**Two files, one stem.** The markdown is for the person. The JSON beside it is
for the tools, because a coverage table an agent typed cannot be counted — so
"how much of the specification is actually tested" stays a number nobody has.
Write both, every time.

File: `{{DELIVERY_DIR}}/qa/{{DATE}}-<kebab-slug>.json`

```json
{
  "version": 1,
  "base": "<the base reference>",
  "date": "<YYYY-MM-DD>",
  "verdict": "<the worst verdict in the matrix>",
  "coverage": [
    {
      "requirement": "<the requirement title, as the specification writes it>",
      "scenario": "<the scenario under it>",
      "verdict": "pass | fail | partial | blocked | not-covered",
      "evidence": "<a test name, a command, or a screenshot path>"
    }
  ]
}
```

The two files must agree. The JSON is the same matrix, not a summary of it: one
object per row of the table below. A verdict outside the five words is read as
`not-covered` by anything downstream, which is the safe direction and not the
one you want to rely on.

File: `{{DELIVERY_DIR}}/qa/{{DATE}}-<kebab-slug>.md`

```markdown
---
title: <one line, what this pass reviewed>
date: <YYYY-MM-DD>
base: <the base reference>
audience: qa
scope: <the change set and the requirements in scope>
verdict: <the worst verdict in this report>
counts:
  pass: <n>
  fail: <n>
  partial: <n>
  blocked: <n>
  not-covered: <n>
  defects: <n>
  change-requests: <n>
---

# <title>

## Scope

The change set, the base reference, the requirements in scope, and the
environment you tested. Name what you left out of scope.

## Coverage

| Requirement | Scenario | Verdict | Evidence |
| --- | --- | --- | --- |

One row per scenario. Evidence is a command output, a screenshot path, or a
test name. An expectation is not evidence.

## Findings

### <F1> — <short title>

- **Breaches:** <requirement title>
- **Severity:** P0 | P1 | P2 | P3
- **Steps:** numbered steps that reproduce the fault
- **Expected:** what the specification says
- **Actual:** what you observed

Repeat one block per finding.

## Visual checks

| Screen | Reference | Result | Diff |
| --- | --- | --- | --- |

## Accessibility

One line per check: keyboard reachability, focus order, focus ring, accessible
names, colour contrast, reduced motion. State the control that failed.

## Not verified

| Item | Why | What it needs |
| --- | --- | --- |

## Change requests

The findings that question the scope. Each one names the requirement that is
absent or wrong, and the decision the team must take.

## Validation

| Command | Result | Reason |
| --- | --- | --- |

Result is `passed` | `failed` | `partial` | `not run`.

Evidence bundle: <path to .agent/evidence/index.html, or why there is none>
```

Build that bundle with `agent-compass evidence` before writing the report, and
put its path on the line above. It collects the test reports and the screenshots
this pass depends on, so a reader can check a verdict instead of trusting it.
Cite it again in the `evidence` cell of any coverage row it proves.

## Rules

- Never fix anything from this skill. It reports; a separate task repairs.
- Never commit and never push. The user commits.
- Never claim a verdict you did not observe. A screenshot or a command output is
  evidence. A plausible expectation is not.
- Quote a requirement by its title, not by its file path.
- Report `not-covered` honestly. A missing test is a finding, not a `pass`.
- Report a defect against the specification, never against a person.
- Say when the specification is silent. Silence is a change request.
