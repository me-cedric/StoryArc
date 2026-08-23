---
name: harvest-questions
description: >
  Read the project specifications and write one RAID register file per open
  question, risk, assumption, issue or dependency. Use when the user asks to
  harvest the open questions, collect the assumptions behind an estimate, fill
  the RAID register, import the spec-kit Clarifications sessions, or find what
  the specs leave undecided.
risk_level: low
writes_files: true
requires_tools: []
license: MIT
metadata:
  version: "1"
---

# Harvest questions

Answer one question for the team: **what do the specifications leave undecided?**

Each finding becomes one file in the RAID register at
`docs/delivery/questions/`. The register holds all five RAID letters in one
shape and one lifecycle. The `kind` field says which letter an item is.

This skill produces questions. It does not produce answers.

## 1 — Read the specifications

Read every specification under `specs/`. When the host project puts its specs
somewhere else, use the host path.

Collect four types of finding:

1. A `[NEEDS CLARIFICATION]` marker.
2. An existing `## Clarifications` session.
3. Hedged prose: "TBD", "to be confirmed", "to be defined", "we assume that",
   "subject to". Match the language the specs are written in.
4. An unstated premise behind an estimate.

Set `kind: assumption` for an unstated premise. Assumptions pay the most,
because an estimate rests on them in silence and no other artifact records
them.

Never invent a finding. Quote the source line for each one.

## 2 — Read the register before you write

List `docs/delivery/questions/` first.

Read the `id`, the `status` and the `specRef` of every file present.

**Never overwrite a file whose `status` is `answered` or `folded`.** Skip it and
report the skip. This rule is absolute. A harvest that erases an answer
destroys the only record of a decision.

**Never overwrite any existing file.** Allocate a new id instead.

**Never delete a register file.** A deleted last file gives its id back to the
allocator, and two different questions then share one id in the git history and
in every ticket that names it. Set `status: folded` instead.

## 3 — Allocate the id

For each file, take the higher of two numbers: the `Q-NNN` in the filename stem,
and the `Q-NNN` in the frontmatter `id`. Both are read. A file named
`Q-020.md` with an empty `id:` key counts as 20.

Take the highest number over all files. Add one. Pad the number to three digits.

An empty register starts at `Q-001`.

Never derive an id from the question text. A reworded question keeps its id.

## 4 — Import an existing Clarifications session

spec-kit records answered questions inside the specification:

```markdown
## Clarifications

### Session 2026-09-03

- Q: Is the prorata calculated per day? → A: Per day.
```

Write one register file per `- Q: … → A: …` pair.

Skip a pair when a register file already holds the same question for the same
`specRef`. Report the skip. Without this check a second run of this skill
duplicates every clarification of the specification.

Set `status: answered` when the `A:` side has text. Set `status: open` when it
is empty. Put the `A:` text in the `## Answer` section.

Set `status: folded` only when the answer is already part of the requirements
of the same specification.

## 5 — Write the files

Read the target path immediately before each write. If it returns content, stop
and take the next id. Minutes pass between step 2 and this step, so the listing
of step 2 is stale and `Write` truncates without warning.

One file per finding, at `docs/delivery/questions/Q-NNN.md`:

```markdown
---
id: Q-014
kind: question
status: open
raisedAt: <YYYY-MM-DD>
raisedBy: assistant
owner:
specRef: specs/billing/spec.md#invoicing
taskRef:
ticket:
---
## Question

<the question, one sentence>

## Answer

## Consequence
```

Rules for the file:

- Emit all nine frontmatter keys. Keep an empty key bare.
- `kind` is one of `question`, `risk`, `assumption`, `issue`, `dependency`.
- `status` is one of `open`, `assigned`, `answered`, `folded`.
- `specRef` names the file and the heading the finding comes from.
- Use the heading `## Question` for every `kind`.
- Leave `## Answer` empty for a new finding.

## 6 — Limits

Write only inside `docs/delivery/questions/`. Never write a specification. The
user folds an answer back into a specification as a separate, reviewed change.

Stop at 20 findings per run. A register of 200 questions is noise.

Do not commit. The user commits.

## 7 — Report

Report three lists:

1. The ids you created, with the `kind` and the source of each one.
2. The ids you skipped, with the reason.
3. The findings you did not write, because the run reached 20.
