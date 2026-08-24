---
id: compass-documentation-chain-followthrough
trigger: 'when you change a specification, a decision record, a design document, a mockup, a data model, an API contract or a costing sheet'
confidence: 0.9
domain: workflow
source: local-repo-analysis
---

# A documentation change is never one file

## Action

Documentation is a chain. When you change one link, every link downstream still
describes last week. No type system and no test suite reports this. The agent
that changed the first link owns the report of what did not follow.

Walk the edges from the artifact you changed:

| Source | Feeds |
| --- | --- |
| Specification | personas, costing, open questions |
| Personas | costing, planning, work split |
| Costing | schedule, impacts, tickets |
| Design document, mockups | specification |
| Decision record | architecture model |
| Work split | impacts, tickets |

Every documentation change also owes two reports, one for each audience:

- [[impact-analysis]] — the developer note: what else must change, and which
  documents are now stale.
- [[delivery-digest]] — the Product Owner digest: the same change in plain
  language, with the scope and planning consequence.

**At the end of the turn, before you report done:**

1. Name each downstream artifact that the change made stale.
2. Say why it is stale, in one line each.
3. Offer to update each one now.
4. Stop. Wait for the answer.

Never update a downstream artifact silently in the same pass. The user has not
read the first change yet. A silent cascade hides the one edit the user wanted
to check.

## The honest boundary

An agent cannot decide if a downstream document is still **true**. Truth needs
the intent behind the change, and the user holds that intent. An agent can only
report that the source moved, and name the documents that quote it.

Report the movement. Do not report a verdict.

## Why

A stale specification costs more than absent code. Code that is wrong fails a
test. A specification that is wrong passes every check, and a team builds from
it for a sprint. The chain has no compiler, so the agent is the only check.
