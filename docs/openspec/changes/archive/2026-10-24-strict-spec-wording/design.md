## Context

The requirements were written to be read, and several carry a table or a paragraph of
reasons before their first scenario. OpenSpec 1.14 measures that text and asks for one
behaviour per requirement, with examples in scenarios.

## Decisions

- **Move, do not cut.** A table becomes a scenario's body; an edge case becomes a scenario
  of its own; a reason that states no behaviour moves below the scenarios. Nothing is
  deleted.
- **SHALL where the code already does it.** Discovery keeps "where the platform permits it"
  in the requirement, so a platform that refuses the local-network permission still meets it.
- **This change exists for the record.** `AGENTS.md` section 3b, rule 3: a main spec is
  written by a sync or an archive, never by hand. The edits were made, measured with the
  strict validation, and then moved here so the archive applies them.

## Risks

Eleven MODIFIED blocks in other active changes are still longer than 500 characters. A
MODIFIED block is not measured, so they pass today; each will warn after its change is
archived unless it is shortened in the same way.
