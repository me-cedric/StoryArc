---
name: delivery-digest
description: >
  Write the Product Owner / Project Manager digest of what changed — plain
  language, business impact, scope and planning consequences, no code. Use when
  the user asks for a status update for the PO, a stakeholder or client summary,
  release notes, a non-technical changelog, or a sprint/delivery report.
risk_level: low
writes_files: true
requires_tools: [git]
license: MIT
metadata:
  version: "1"
---

# Delivery digest

The same change, told to the person who owns the *what* and the *when* rather
than the *how*. Its twin is [`impact-analysis`](../impact-analysis/SKILL.md),
which serves the developers.

**Compartmentalisation is the point.** The digest is the file that gets
forwarded — to a client, into a steering committee deck, onto a wiki. Write it
so that forwarding it is safe.

## Read before writing

1. The change: `git diff --stat <base>...HEAD` and `git log <base>..HEAD`.
2. The developer note, if it exists: `docs/delivery/impacts/`. Reuse its
   findings — do not re-derive them differently.
3. The requirements the change serves: `specs/`.
4. Who is affected: `docs/delivery/personas.json` and
   `docs/delivery/assignments.json`.
5. The cost frame, when planning moved: `docs/delivery/costing/*.json`
   (`mandays`, `moscow`, `priority`).

When the host project puts an artifact somewhere else, use the host path.

## Translate, do not summarise

Every line answers *so what?* for delivery.

| Instead of | Write |
| --- | --- |
| a file or module name | the feature or screen the user sees |
| a refactor | "no visible change; reduces the risk of X" — or drop it |
| an endpoint | the action it enables, and for whom |
| a migration | whether there is downtime, and whether data is affected |
| a library bump | only if it changes behaviour, cost, or a compliance answer |

Group by **feature**, never by commit and never by file.

## Redaction rules — non-negotiable

Never put in this file:

- secrets, tokens, keys, connection strings, internal hostnames or IPs
- file paths, function names, stack traces, SQL, code snippets
- individual names attached to a judgement ("X was late", "Y broke it")
- internal disagreements, or anything said in confidence
- vulnerability detail beyond "a security fix was applied in <area>"

Refer to work by **profile** (`Backend developer`), not by person, unless the
user explicitly asked for named attribution.

If a change genuinely cannot be described without one of the above, write the
business consequence and add `Technical detail available on request.`

## Output

File: `docs/delivery/digests/<YYYY-MM-DD>-<kebab-slug>.md`

```markdown
---
title: <one line a PO would recognise>
date: <YYYY-MM-DD>
base: <the base reference>
audience: product
---

# <title>

**In one sentence:** …

## What is now available

- **<Feature>** — what a user can do that they could not before.

## What changed for users

Behaviour that moved for someone already using the product. `None.` if nothing did.

## Scope and planning

| Item | Before | Now | Why |
| --- | --- | --- | --- |

Only rows where scope, priority, MoSCoW or effort actually moved.

## Decisions taken

One line per decision, with what it rules out. Link the decision record by title.

## Waiting on

| What we need | From whom | Blocking | Since |
| --- | --- | --- | --- |

This is the section the reader acts on. Be specific and be honest about dates.

## Risks and watch points

Plain language. What might slip, and what would tell us early.

## Not in this delivery

Explicitly out of scope, so nobody assumes it landed.
```

## Rules

- No jargon without a plain-language gloss on first use.
- Numbers only when you can source them. "Faster" without a measurement is noise.
- Never mark something delivered because a task is ticked — it counts only when
  it is wired and tested end to end. See
  [`verified-progress-signal`](../../knowledge/instincts/verified-progress-signal.md).
- `Waiting on` rows must name a person or a role, never "the team".
- Do not commit or push. The user commits.
