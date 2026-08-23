---
name: adr-from-meeting
description: >
  Turn a meeting transcript, call notes, or a decision discussion into an
  Architecture Decision Record under docs/decisions/. Use when the user pastes
  meeting notes or a transcript and wants the decision captured, or says
  "generate an ADR from this", "record this decision", or "write it up as an ADR".
risk_level: low
writes_files: true
requires_tools: []
---

# ADR from a meeting — capture the decision while it is fresh

Mission: a structuring decision discussed in a meeting becomes a durable
Architecture Decision Record at `docs/decisions/NNN-title.md`, using the
project's decision template, with the rejected alternatives **and their reasons**
preserved — so the "why we did / did not do X" survives the people who were in
the room.

## When to use

Reach for this when a discussion settled (or is settling) a decision that is
**structuring and costly to reverse**: architecture, a shared or public contract,
a data-ownership or module boundary, a build-vs-buy, a cross-cutting convention.
Skip it for reversible, local choices — those live in the code and the module's
`DESIGN.md`.

For a *new project's* upfront architecture, use `architecture-advisor` and the
architecture-decision workflow instead; this skill is for the ongoing decisions
that accrue as a project runs.

## Steps

1. **Locate the log.** Find `docs/decisions/`. If it is missing, create it and
   copy `000-template.md` in as the shape to follow. The next number is the
   highest `NNN` + 1 (zero-padded); the title is kebab-cased, e.g.
   `007-event-bus-choice.md`.
2. **Extract, do not invent.** From the transcript pull: the problem and forces,
   the options weighed, the pros and cons voiced for each, the option chosen, the
   stated reasons, and the consequences and follow-ups people raised. Attribute
   nothing the transcript does not support.
3. **Preserve the rejected paths.** Every option discussed and dropped gets its
   block with *why it lost*. This is the highest-value part — it stops the team
   re-litigating the same choice in six months.
4. **Fill the template.** Map to context and problem → decision drivers →
   considered options (with pros and cons) → decision → consequences → links.
   Leave `Status: proposed` unless the meeting explicitly ratified it
   (`accepted`); set Date to the meeting date.
5. **Flag the gaps.** Anything the meeting left open becomes an explicit open
   question or a follow-up under Consequences — never a confident invention.
6. **Interconnect** — wire the ADR to the rest of the docs (see below).
7. **Confirm.** Report the drafted ADR path and a one-line summary; do not bury
   it in prose.

## Interconnection

An ADR is independent from a module's `DESIGN.md` / `README.md`, but link both
ways when it helps:

- From the **affected module's `DESIGN.md` / `README.md`**, cite the ADR as the
  *why* behind a structural choice ("a bus over direct calls — see decision 007")
  instead of re-explaining it inline.
- From the **ADR's Links**, point back at the module docs, the spec or issue, and
  the PR that implements it.
- If the decision reveals a **reusable pattern or gotcha**, promote it to a
  `knowledge` instinct; if a durable running note fits better, log a `projectmem`
  decision (`pjm decision`). The ADR stays the canonical record; the instinct and
  log are fast-recall echoes.
- **Supersede, do not rewrite.** A reversed decision gets a *new* ADR, and the
  old one flips to `superseded by NNN`.

## Validate

- Every template section is filled or explicitly marked N/A — no empty headings.
- At least one rejected option with its reason (or a note that none were raised).
- The number is unique and sequential; the filename matches the title.
- No invented facts, names, or numbers beyond what the transcript supports.
