# StoryArc — Claude Agent Guide

Read [`AGENTS.md`](AGENTS.md) first. It carries the project-specific contract and
takes precedence over the agent-compass baseline vendored at
[`docs/agent-compass/`](docs/agent-compass/AGENTS.md).

## Slash commands available here

| Command | Use |
| --- | --- |
| `/opsx:explore` | Think through a capability before committing to it |
| `/opsx:propose "<idea>"` | Create a change proposal with proposal, specs, design and tasks |
| `/opsx:apply` | Implement an approved change |
| `/opsx:sync` | Merge a change's delta specs into the main specs |
| `/opsx:archive` | Retire a completed change |

**Every behaviour is specified before it is built.** If what you are about to
implement is not in `docs/openspec/specs/`, propose it first.

The OpenSpec root is `docs/openspec`. The CLI resolves it from `docs/`, so run
`cd docs` before any `openspec` command, or use the `pnpm spec:*` scripts.
