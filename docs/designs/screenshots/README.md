# Screenshots

This folder keeps only the screenshots that a lasting document shows: the README, an ADR,
a design document, `docs/mvp-device-checklist.md` or `docs/openspec/STATUS.md`.

A screenshot that checks a change does not come here. Take it in `.build/screens/`, look at
it, and delete it. [AGENTS.md](../../../AGENTS.md) section 6 gives the rules.

## The screenshots that were removed

On 2026-10-10 the owner asked for a smaller repository. 1,517 screenshots of old sweeps and
proofs left this folder. Task lists and archived changes still name some of them.

Git history keeps each one. To get one back:

```bash
git log --diff-filter=D --format=%h -1 -- <path>     # the commit that removed it
git show <commit>^:<path> > shot.png                  # the file as it was before
```
