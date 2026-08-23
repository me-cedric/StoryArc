---
name: working-style-skills
description: "Use when the user asks to change how you communicate or how much you build — be terse, use fewer tokens, caveman mode, stop over-engineering, be lazy, YAGNI, simplest solution, action-first output, no preamble, or rewrite text so another agent cannot misread it. Installs the tracked style skill that matches the request and applies the compass precedence rules when several are active. Triggers: caveman, ponytail, i-have-adhd, asd-ste100, be brief, less tokens, terse, minimal solution, do less, over-engineered, bloat, boilerplate, simplify this, STE100, plain-language rewrite, just give me the steps."
risk_level: low
writes_files: false
requires_tools: []
version: 1.0.0
---

# Working Style Skills

Ten output-shape skills are tracked across four external sources. Agent Compass
keeps no copy of them and installs the one the user asked for.

| Skill | Source | Shapes |
| ----- | ------ | ------ |
| `ponytail` (+ `-audit`, `-review`, `-debt`, `-help`) | [`DietrichGebert/ponytail`](https://github.com/DietrichGebert/ponytail) | How much you build. Forces the laziest solution that works: YAGNI, standard library before a dependency, one line before fifty. |
| `caveman` (+ `-commit`, `-review`) | [`JuliusBrussee/caveman`](https://github.com/JuliusBrussee/caveman) | How many tokens you spend. Ultra-compressed output at full technical accuracy. |
| `i-have-adhd` | [`ayghri/i-have-adhd`](https://github.com/ayghri/i-have-adhd) | Output order. Numbered steps, no preamble, one concrete next step. |
| `asd-ste100` | [`danyuchn/asd-ste100-skill`](https://github.com/danyuchn/asd-ste100-skill) | Ambiguity in durable text. Controlled language for commits, docs, errors, and instructions handed to another agent. |

These are **user preference**. Never turn one on because the task looks like it
would suit one. Install and apply them when the user asks.

## Procedure

### 1. Install what the user asked for

```bash
# User-wide is usually right: a style preference is about the person, not the repo
agent-compass external-skills --source ponytail --recommended --global
agent-compass external-skills --source caveman --recommended --global
agent-compass external-skills --source i-have-adhd --recommended --global
agent-compass external-skills --source asd-ste100 --recommended --global

# Per-project, when a team wants the house style in the repo
agent-compass external-skills . --source caveman --recommended
```

This writes `.claude/skills/`, `.codex/skills/`, and `.agents/skills/` for the
user scope, so Claude Code, Codex, and Copilot all see them.

`caveman` publishes 20 skills; Agent Compass curates 3. The other 17 either
duplicate a compass workflow or restate a rule `AGENTS.md` already sets. Install
one by name only after reading it.

### 2. Apply the precedence rules when several are on

The four combine into one contract, and they conflict in predictable places. The
full precedence table is in
[style-contract.md](../../docs/guidelines/style-contract.md). The short form:

1. **`ponytail` decides scope, the others decide presentation.** How little to
   build is settled before how to say it.
2. **`i-have-adhd` decides order**: the concrete action comes first, no preamble.
3. **`caveman` decides density** for conversational output.
4. **`asd-ste100` overrides `caveman` for durable text.** A commit message, a doc,
   an error string, or an instruction handed to another agent is read later
   without you, so it gets the unambiguous form — `caveman` compresses and allows
   fragments, `asd-ste100` forbids ellipsis and requires an explicit subject.

### 3. What a style skill may never remove

Compression changes wording. It does not remove a required part of the answer.

- The Completion Gate (`AGENTS.md` §4) still owes changed files, the exact
  commands run, a result per command, whether a failure is pre-existing, and the
  remaining risks. Terse is fine; missing is not.
- Reasoning, risks, and verification results survive compression. If a rule
  forces you to drop one, the rule is being misapplied.
- `ponytail` argues for less code. It never argues for skipping a test, a
  validation run, or a security control.

### 4. Propagate to sub-agents deliberately

A sub-agent does not inherit the user's style preference. When you delegate and
the returned text reaches the user, say which style applies — and tell the
sub-agent that its returned text is durable text, so `asd-ste100` governs it. See
[style-contract.md](../../docs/guidelines/style-contract.md).

## Freshness

```bash
agent-compass upstream-skills --check-updates
agent-compass upstream-skills --update caveman --dry
```

## Related

- [style-contract.md](../../docs/guidelines/style-contract.md) — the precedence
  table and the sub-agent propagation rule.
- [style-and-design-skills.md](../../docs/tooling/style-and-design-skills.md) —
  install routes and the tracked inventories.
- [`agent-teacher`](../agent-teacher/SKILL.md) — when the user wants to be taught
  rather than have the output reshaped.
