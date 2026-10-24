---
name: grill
description: Interview the user about a plan until each open question has an answer or an owner. Writes one RAID file per open question and one ADR per decision. Use to stress-test a plan or to fill the RAID register.
risk_level: low
writes_files: true
requires_tools: []
disable-model-invocation: true
---

# grill

## Loop

1. If the upstream skill `grill-me` or `grilling` is installed (source id `mattpocock`), follow its loop.
   Else use steps 2 to 5. To install it, add `mattpocock` to `upstream` in `.agents/compass.json`, then run `ac sync`.
2. Read the plan, `docs/openspec` and the code that the plan touches. Answer from them first.
3. Ask one question at a time. Give your recommended answer with each question.
4. Ask the question that unblocks the most other questions first.
5. Stop when no open question blocks the plan, or when the user says stop.

## Harvest

Also scan `docs/openspec` for findings:

1. A `[NEEDS CLARIFICATION]` marker.
2. A `## Clarifications` session. Each `- Q: <question> → A: <answer>` line is one finding.
3. Hedged prose such as "TBD", "to be confirmed", "we assume", "subject to". Match the language of the specs.
4. An unstated premise behind an estimate in `docs/costing`. Set `kind: assumption`.

Quote the source line for each finding. Never invent a finding. Stop at 20 findings for each run.

## RAID files

Write one file for each finding: `docs/delivery/questions/Q-NNN.md`.

```markdown
---
id: Q-014
kind: question
status: open
raisedAt: <YYYY-MM-DD>
raisedBy: assistant
owner:
specRef: <spec path>#<heading>
taskRef:
ticket:
---
## Question

<one sentence>

## Answer

## Consequence
```

- Write all nine keys. Keep an empty key bare.
- `kind` is `question`, `risk`, `assumption`, `issue` or `dependency`.
- `status` is `open`, `assigned`, `answered` or `folded`.
- Take the highest `Q-NNN` of all file names and all `id` keys. Add one. Pad to three digits. An empty register starts at `Q-001`.
- A reworded question keeps its id.
- List the register first. Read the target path again just before each write. If it has content, take the next id.
- Never overwrite a file. Skip a clarification when a file holds it for the same `specRef`.
- Never delete a file. Set `status: folded` instead.
- Put an answer under `## Answer`. Set `status: answered`. A clarification pair without an answer is `open`.
- Do not edit a spec. The user folds an answer into the spec as a separate change.

## ADRs

Write each decision that the user makes as an ADR in `docs/decisions`. Use the skill `adr`.

## A document for a decider

Read `references/decider-view.md` when the user asks for a document to send to a decider.

## Report

Report three lists:

1. The ids that you created, with kind and source.
2. The ids that you skipped, with the reason.
3. The findings that you did not write.

Do not commit.
