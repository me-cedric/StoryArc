---
id: provisioning-state-registry
trigger: 'when a tool writes managed files into a repository it does not own (scaffolding, skill sync, config install, template refresh) and must report what is current, stale, or no longer shipped'
confidence: 0.9
domain: workflow
source: local-repo-analysis
---

# Model provisioned files as four states, and never delete an orphan

A tool that installs files into someone else's repository needs one model for
every file it manages, whatever the kind. Ad-hoc per-kind logic produces a tool
that refreshes some files and forgets others.

## The four states

| State | Meaning | Action |
| --- | --- | --- |
| `missing` | the tool ships it, the repository does not have it | install |
| `current` | present, and matches the shipped version | nothing |
| `outdated` | present, and the shipped version moved | refresh |
| `orphan` | present, and the tool no longer ships it | **report only** |

`orphan` never becomes a deletion. The file may be a local customization, or
work in progress, or something the team now maintains itself. Report it and let a
human decide. A tool that deletes an orphan destroys work it cannot see.

## One registry over every kind

Register every managed artifact in one table — skills, contract files, host
config, policy packs — with a kind, a key, and a state. One model means:

1. One code path computes states, so no kind is silently unmanaged.
2. The report is complete by construction.
3. Adding a kind is a table entry, not a new branch.

Compute the orphan set against the union of names shipped by **all** trees, not
one tree at a time. Otherwise a file shipped by tree B is reported as an orphan
of tree A.

## Record what was written, in the repository

Write a ledger of what the tool installed, at what version, into a git-tracked
file in the target repository. Then every teammate sees the same state after a
clone, and `outdated` is a fact rather than a guess from file content.

## Seed versus managed

Two kinds of installed file need two rules:

- **seed** — copied once, then the host owns it. Never refreshed. Edits are safe.
- **managed** — the tool keeps it current. Edits are erased on the next refresh.

Say which one a file is, in the file itself when it is a text artifact. A user who
edits a managed file and loses the edit was not warned by the tool.

## Never overwrite on install

An install path creates missing files only. A refresh path is a separate,
explicit action against files the ledger says the tool owns.
