---
id: one-artifact-root
trigger: 'when an agent or a tool writes a generated artifact — a specification, a decision record, a diagram, a report — into a repository that configures where each kind lives'
confidence: 0.9
domain: workflow
source: local-repo-analysis
---

# One root per artifact kind, resolved before the first write

A tool that reads artifacts reads one directory per kind. An artifact written
anywhere else produces nothing: the file exists, the writer reports success, and
no reader ever opens it.

Two roots for one kind is worse than a wrong root. Half the artifacts get read,
so the gap looks like missing work instead of a configuration fault.

## Read the declaration first

Keep the locations in one machine-readable file, and read it before you write:

```json
{
  "paths": {
    "specs": "docs/specs",
    "decisions": "docs/decisions",
    "diagrams": "docs/diagrams"
  }
}
```

A conventional path is a guess. A repository-root `specs/` looks correct and is
still the wrong root when the declaration names another one.

## Say which root you used

When the declaration has no entry for the kind, fall back to the documented
default and state the path you chose in your report. A silent fallback hides the
moment the declaration went stale.

## The declaration has one writer

Name the owner of the file and keep every other writer out. A file that both a
tool and a human edit drifts, and the drift moves artifacts without any change
to the writer's code.

## Make every writer resolve, not remember

Resolve the root through one shared helper. A path copied into a second writer
is a second root as soon as the declaration changes. This is the same failure as
a duplicated resource list, which is why one declaration plus one resolver is the
whole pattern. The same declaration deserves a printed-resolution gate; see
[`vendored-corpus-manifest`](vendored-corpus-manifest.md).

When the same file also records what a tool installed, see
[`provisioning-state-registry`](provisioning-state-registry.md).
