# Architecture diagrams

A [LikeC4](https://likec4.dev) model of StoryArc, at the C4 context, container
and component levels.

**Every `.c4` file here is self-contained** — its own `specification`, its own
`model`, its own `views`, one diagram per file. The specification block repeats
in all six. That duplication is deliberate, and the next section says why.

| File | Level | What it answers |
| --- | --- | --- |
| `context/context.c4` | Context | What is StoryArc, who uses it, and what does it talk to? |
| `ios-containers/ios-containers.c4` | Container | What is inside `apps/ios`, and what depends on what? |
| `android-containers/android-containers.c4` | Container | The same question for `apps/android`. |
| `shared-artefacts/shared-artefacts.c4` | Container | What do the two apps actually share? |
| `ios-format-components/ios-format-components.c4` | Component | Inside `StoryArcKit/Formats`. |
| `android-format-components/android-format-components.c4` | Component | Inside `:core:format`, beside its iOS mirror. |

## The loader contract, and why the files repeat themselves

Konvoy is what actually renders these diagrams, and it renders one by calling:

```ts
const likec4 = await LikeC4.fromSource(previewText);
const layouted = await likec4.layoutedModel();
```

`fromSource` takes **one file's text**. It does not read the directory. So a
model split across `specification.c4` + `model.c4` + `views.c4` — which is the
ordinary LikeC4 layout, and which this folder used until now — gives Konvoy a
`views.c4` whose every reference points at a `model.c4` it cannot see.

Two things made that failure silent:

1. **`fromSource` does not throw** on unresolved references. It logs
   `Source not resolved`, then returns a model anyway. Konvoy's `try/catch`
   never fires, so the page shows a diagram frame with nothing in it.
2. **`likec4 validate <dir>` parses the directory as a workspace**, so it was
   green on exactly the layout that could not render. Validation never had a
   chance to catch this.

Hence the rule: **one diagram, one file, no cross-file references.** Accept the
repeated `specification` block. It is the price of the loader's contract, not a
smell to engineer away.

This is a file-layout problem, not a version problem — Konvoy pins
`likec4: ^1.59.2`, the same version used here.

## Why each diagram sits in its own directory

Self-containment and the workspace CLI pull against each other. Six files that
each declare `element app` and `ios = app '…'` are six *duplicate* declarations
when the CLI parses the folder as one model:

```
Duplicate element kind 'app'
Duplicate element name ios
```

A LikeC4 **project** is scoped to a directory. So each diagram gets a directory
and a `likec4.config.json`, and the six become six independent projects that
never see each other. The alternative — keeping the files flat and prefixing
every element kind and every element id per file (`ctxApp`, `ctxIos`, …) — would
have made the CLI happy by making the diagrams worse to read, and the diagrams
are the deliverable.

Konvoy lists `.c4` files recursively, so all six still appear in its sidebar,
named by their file name.

The cost of this choice is that the CLI needs to be pointed at one diagram
directory rather than at the folder — see below, including one command that
gets it silently wrong.

## Checking your work

### The check that matters: load each file the way Konvoy does

```bash
npx --yes --package likec4@1.59.2 -- node docs/diagrams/check.mjs
```

(Note `--package … -- node`, not a bare `npx likec4`: the script needs the
library, not the CLI. It resolves `likec4` from the throwaway package `npx`
puts on `PATH`, so this installs nothing into the repo. `npm install` inside
`docs/diagrams` does **not** work — npm trips over the pnpm workspace root.)

`check.mjs` calls `LikeC4.fromSource` on **each file on its own** and fails
loudly on two things:

- **any diagnostic** — because `fromSource` tolerates errors and returns a model
  regardless, so `hasErrors()` has to be asked explicitly; and
- **any view with zero nodes** — because a view that parses but draws nothing is
  the exact failure this layout exists to prevent.

> `view.nodes` and `view.edges` are **zero-argument generator methods**, not
> arrays. `view.nodes.length` is the *function's arity* and reads `0` for a
> perfectly good file — which is how an earlier probe reported success on a
> broken model. The real counts are `[...view.nodes()].length` and
> `[...view.edges()].length`.

### The CLI, second — and point it at ONE diagram

```bash
npx likec4 validate docs/diagrams --no-layout        # all six: syntax + semantics
npx likec4 validate docs/diagrams/context            # one diagram, layout included
npx likec4 export png -o out docs/diagrams/context   # one diagram, correct output
npx likec4 start docs/diagrams                       # viewer, project switcher
```

**The path you give the CLI should be a single diagram's directory.** That
directory is one project with one model, so every command behaves normally.
Aimed at the parent folder instead, the CLI sees six projects and misbehaves in
two different ways:

- `validate docs/diagrams` fails its layout stage with `Specify exact project`.
  Add `--no-layout` to sweep all six for syntax and semantics in one go.
- **`export docs/diagrams -p <name>` silently exports the WRONG diagram.** In
  likec4 1.59.2 the export command ignores `--project`: it renders the
  alphabetically first project every time, and writes it into a folder named
  after the project you asked for. Three different `-p` values produced three
  byte-identical PNGs under three different names. Never export from the parent
  folder; there is no error to warn you.

`likec4` is not a project dependency and does not need to be; nothing in the
build reads these files.

### `validate` is necessary, not sufficient

`likec4 validate` parses, resolves every reference, and computes a layout for
every view. All of that passed on two views that then rendered as a **blank
canvas** in `likec4 start` — no error, no console warning, nothing on screen.

Both failures were the same shape: a view pulled in a lone element from another
branch of the model without naming its parent. Adding the parent to the
`include` list fixed both. That is why the component views include `shared`
alongside `shared.libarchive`, and the comment saying so is load-bearing.

> **Look at every view you changed before you commit it.** A view that
> validates has not been proven to draw.

Either open it in `likec4 start`, or export it and open the PNG:

```bash
npx likec4 export png -o /tmp/c4 docs/diagrams/<diagram>
```

That rule was learned the hard way, and the split-model defect above makes it
doubly true: a green check is not a rendered diagram. `check.mjs` now automates
the node-count half of it, but only the eye catches a view that draws the
*wrong* thing — and, as the export trap above shows, a rendered PNG is only
proof when you rendered the diagram you think you did.

## What the model is trying to say

Three facts about this repository are easy to get wrong from the file tree
alone, and the model exists mostly to state them.

**There are two products, not one.** `apps/ios` and `apps/android` share no
code and no runtime ([ADR-0001](../decisions/0001-independent-native-cores.md)).
The context view has no edge between them, and that missing edge is the point.
What keeps them the same app is a written contract and two generated artefacts —
capability specs, design tokens, and a test-fixture corpus both suites assert
against.

**There is no server.** The context view draws a *deliberately absent* element
for the StoryArc service that does not exist. No backend, no accounts, no
analytics, no crash reporting: every arrow leaving an app lands on something the
reader owns or chose. It is the only element in the model that does not
correspond to code, and it is drawn dashed and muted so it cannot be mistaken
for one that does.

**The format layer is mirrored on purpose.** It is the one layer written twice
deliberately rather than merely specified, because it has already produced a
silent cross-platform divergence. The two component views are meant to be read
side by side: the spine matches type for type, and the three components that do
not — `SafTree`, `UriSource`, `DocumentFolderArchive` — exist because Android
does not hand an app a path for a user-picked folder.

## The rule that keeps this honest

**This model describes structure. The source is authoritative when they
disagree.**

Nothing validates these files against the build. Every element here was
transcribed from `apps/ios/Packages/*/Package.swift`, `apps/ios/project.yml`,
`apps/android/settings.gradle.kts` and the `build.gradle.kts` files, and every
component from a type that exists in the named module — but a module renamed
tomorrow will be wrong here and right there.

So: if a diagram and a build file disagree, the build file wins and the diagram
is a bug. Fix it in the same change that moved the code. If you cannot verify an
element against a build file or a source file, do not add it — a diagram that
shows a component nobody wrote is worse than one that shows fewer, true things.

Because each file now stands alone, a module renamed in the build has to be
renamed in **every** diagram that shows it. `grep` the folder; do not trust that
one edit reached them all.
