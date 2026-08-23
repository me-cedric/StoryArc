# projectmem

This project may use `projectmem` for durable local agent memory.

Setup:

```bash
pip install projectmem
pjm init
```

Sharing model (why this is set up backwards from projectmem's default):
`events.jsonl` is the append-only source of truth; every other file is a
projection rebuilt by `pjm regenerate`. Sharing a regenerated file overwrites
teammates; sharing the append-only log merges cleanly. So:

- **Commit `.projectmem/events.jsonl`** — the shared source of truth.
  `.gitattributes` gives it `merge=union` so concurrent appends auto-combine.
- **Do not commit** `.projectmem/summary.md`, `PROJECT_MAP.md`,
  `AI_INSTRUCTIONS.md`, `issues/`, watch/data/DB files — they are gitignored and
  rebuilt from the log.
- **After `git pull`/merge, run `pjm regenerate`** (the `post-merge` hook does it
  automatically) to fold teammates' events into your local summary.
- The committed log crosses into git, so review it for secrets/PII/local paths.
- Backfill/import commands can create many legacy issue files. Run them only
  when the team opts in.

Daily agent workflow:

- Before work: read relevant summaries and run pre-action checks.
- During work: log failed attempts and important findings.
- After work: log decisions, fixes, changed files, validation, and risks.
- Durable architecture/design decisions: also record an ADR in
  `docs/decisions/` (one file per decision merges without conflict) — don't leave
  them only in the regenerated summary.

Do not log secrets, credentials, tokens, personal data, or temporary
brainstorming.

See `projectmem-policy.md` for the project memory policy.
