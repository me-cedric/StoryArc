# Agent Trace & Outcome Log

Improvement needs evidence. Without traces a team only remembers the last bad
run. This is a lightweight, append-only log of what agents did and how it went —
**never** a place for secrets, credentials, or personal data.

## Format

One JSON object per line (`.jsonl`). Required fields: `task`, `type`,
`validation`, `outcome`. Optional: `ts`, `tools`, `corrections`, `lesson`.

```text
{"ts":"2026-06-20","task":"fix login redirect loop","type":"bugfix","tools":["read","edit","bash"],"validation":"passed","outcome":"fixed","corrections":1,"lesson":"guard order matters"}
```

- `type`: bugfix | feature | refactor | docs | chore | research
- `validation`: passed | failed | partial | not run
- `outcome`: short result (fixed, shipped, reverted, blocked, …)
- `corrections`: number of human corrections needed (a friction signal)
- `lesson`: one durable takeaway — promote recurring ones via
  [`../../docs/workflows/knowledge-capture.md`](../../docs/workflows/knowledge-capture.md)

## Rules

- No secrets, tokens, credentials, raw prompts, or personal data. The validator
  rejects rows that look like they contain them.
- Keep the file local/ignored unless the team agrees to commit anonymized rows.
- Validate with `node scripts/agent-trace.mjs --file <path>`.

## Why JSONL

Append-only, diff-friendly, greppable, and trivial to roll up. Read high-`corrections`
or `failed` rows when deciding the next instruction, skill, hook, or check to add
(see [`../../docs/workflows/agent-improvement-loop.md`](../../docs/workflows/agent-improvement-loop.md)).
