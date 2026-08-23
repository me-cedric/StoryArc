---
name: work-splitting
description: >
  Split a backlog of work-items across people or agents with clear separation of
  concern, minimal file overlap, explicit coordination seams, and a shareable
  assignment brief per owner. Use when dividing work across a team, deciding who
  does what, or parallelizing work so contributors don't collide.
risk_level: low
writes_files: false
requires_tools: []
---

# Work Splitting

Divide work so contributors rarely touch the same files and every hand-off is
explicit. Optimize for *no overlap*, not equal line counts.

## When to use

- Allocating a backlog across a team or multiple agents.
- "Who should do what?" / "split this so we don't step on each other."
- Setting up parallel workstreams before implementation.

## Method

1. **Assign by module/domain tree, not by task.** Give each owner a
   self-contained set of directories — one writer per file at any time. Whole
   domains beat scattered tasks.
2. **Match work to the owner** on capability and context (isolated/independent
   trees suit remote or autonomous work; cross-cutting foundations suit the
   coordinator). Keep any private rationale out of the shared message.
3. **Name the coordination seams.** Where two owners' work meets, apply the rule
   *owner exposes (service + shared contract), consumer wires on top* — never two
   people editing the same file. List each seam explicitly.
4. **Sequence the foundations first** — the shared pieces everyone consumes
   (auth, contracts, notification/event cores) go to whoever unblocks the rest.

## Output

Per owner: scope (modules), specs/requirements, tracker tickets, concrete first
steps, coordination seams, and any gates. Plus a shared **assignment brief** safe
to send as-is — state assignments and hand-offs, never private notes about
individuals. Flag the single biggest overlap risk and how it is contained.
