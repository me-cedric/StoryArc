# StoryArc — Claude Agent Guide

Read [`AGENTS.md`](AGENTS.md) first. It carries the project-specific contract and
takes precedence over the agent-compass baseline vendored at
[`docs/agent-compass/`](docs/agent-compass/AGENTS.md). §3b of that file holds the
OpenSpec rules; this page is the command list.

## Slash commands available here

All twelve OpenSpec workflows are installed. Pick by what you actually want.

| Command | Use | Writes code |
| --- | --- | --- |
| `/opsx:explore` | Think through a capability before committing to it | never |
| `/opsx:new` | Scaffold a change, then step through its artifacts one at a time | never |
| `/opsx:propose "<idea>"` | Scaffold **and** write every planning artifact in one pass | never |
| `/opsx:ff "<idea>"` | Fast-forward: only what is needed to start implementing | never |
| `/opsx:continue` | Write the **next** artifact the status gate calls `ready` | never |
| `/opsx:update` | Revise an existing plan and make its artifacts agree again | never |
| `/opsx:apply` | Implement an approved change, ticking each task as it passes | yes |
| `/opsx:verify` | Check the code against the requirements before archiving | never |
| `/opsx:sync` | Merge a change's delta specs into the main specs | never |
| `/opsx:archive` | Retire a completed change and update the main specs | never |
| `/opsx:bulk-archive` | Several completed changes at once | never |
| `/opsx:onboard` | Guided first cycle, narrated | yes |

These files are generated from the installed CLI's own templates by
`pnpm openspec:workflows`. Do not hand-edit them — `pnpm lint` fails on the drift.

## The three things that catch every agent

1. **Every behaviour is specified before it is built.** If what you are about to
   implement is not in `docs/openspec/specs/`, propose it first. And read the
   capability's row in [`STATUS.md`](docs/openspec/STATUS.md) before claiming it is
   missing — several capabilities are further along than an older proposal assumes.
2. **The OpenSpec root is `docs/openspec`, and the CLI resolves the nearest one.**
   Run `cd docs` before any `openspec` command, or use the `pnpm spec:*` scripts.
   Print the resolved root in your handoff.
3. **`pnpm spec:validate` is not the completion gate.** It checks the files a
   change has. `pnpm spec:guard` checks the ones it should have, and
   `openspec status --change <name> --json` says which artifact is next.

```bash
pnpm spec:guard          # artifact chain, one root, config, installed workflows
```
