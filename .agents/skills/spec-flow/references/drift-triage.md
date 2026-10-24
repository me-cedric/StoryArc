# Drift triage

Use this when a spec changes after tickets exist.

1. Read `git diff <base>...HEAD -- docs/openspec`. Name the criterion that changed, not the hunk.
2. Say what did not move. Keep the note to five lines for each ticket.
3. Write one line for each ticket: `<KEY> · <what moved> → <action>`.
4. The action is one of: update the description, comment only, re-estimate, split into a new ticket, no action.
5. A typo or a reformat needs no action. A new requirement needs a new ticket.
6. Flag a change-request candidate when any of these is true:
   - A requirement or scenario is new.
   - An estimate must grow.
   - Finished work needs rework.
   - A date or scope moves.
7. Write the flag. The contract owner makes the decision.
8. Do not edit `docs/delivery/tickets.json`. Konvoy writes it. For a ticket that a human edited, comment only.
9. Write the note to `docs/delivery/drift/<YYYY-MM-DD>-<slug>.md`.
