# Architecture diagrams

A [LikeC4](https://likec4.dev) model of StoryArc, at the C4 context, container
and component levels.

| File | What is in it |
| --- | --- |
| `specification.c4` | The notation: element kinds, relationship kinds, tags. |
| `model.c4` | The two apps, their build modules, the shared artefacts, the outside world. |
| `components.c4` | The format layer on both platforms, type by type. |
| `views.c4` | The six views. |

## The views

| View | Level | What it answers |
| --- | --- | --- |
| `index` | Context | What is StoryArc, who uses it, and what does it talk to? |
| `iosContainers` | Container | What is inside `apps/ios`, and what depends on what? |
| `androidContainers` | Container | The same question for `apps/android`. |
| `sharedArtefacts` | Container | What do the two apps actually share? |
| `iosFormatComponents` | Component | Inside `StoryArcKit/Formats`. |
| `androidFormatComponents` | Component | Inside `:core:format`, beside its iOS mirror. |

## Viewing it

```bash
npx likec4 start docs/diagrams      # local viewer, hot reload
npx likec4 validate docs/diagrams   # parse, resolve and lay out every view
npx likec4 export png -o out docs/diagrams
```

`likec4` is not a project dependency and does not need to be. Nothing in the
build reads these files.

### `validate` is necessary, not sufficient

`likec4 validate` parses, resolves every reference, and computes a layout for
every view. All of that passed on two views that then rendered as a **blank
canvas** in `likec4 start` — no error, no console warning, nothing on screen.

Both failures were the same shape: a view pulled in a lone element from another
branch of the model without naming its parent. Adding the parent to the
`include` list fixed both. Whatever the precise rule is, the practical one is:

> **Open every view you changed in `likec4 start` before you commit it.** A view
> that validates has not been proven to draw.

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
