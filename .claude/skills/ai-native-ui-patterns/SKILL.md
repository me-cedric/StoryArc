---
name: ai-native-ui-patterns
description: Build the UI for AI-native interfaces — streaming answers with citations, reasoning traces, tool-call chips, approval gates, agent task rows, prompt composers, confidence meters, proposed-diff tables. Use when implementing or reviewing any surface where a model or agent is the thing the user works with.
risk_level: medium
writes_files: true
requires_tools: []
---

# AI-Native UI Patterns

A conventional interface renders state that already exists. An AI-native
interface renders **work in progress, the evidence behind it, and how sure the
model is** — then asks permission before it changes anything. Those four things
are the whole job. A surface that has them feels like a colleague; a surface
that skips them feels like a slot machine.

This skill owns **behaviour and structure**. It does not own taste — pair it
with a visual-direction skill (`high-end-visual-design`, `minimalist-ui`,
`industrial-brutalist-ui`) and with the host's design system.

## 1. The seven laws

1. **Never show an unqualified spinner.** Latency is the dominant interaction.
   Every wait states *what phase it is in* and *how long it has run*
   ("Reading exports · 2.4s"). A bare spinner is a bug report waiting to happen.
2. **Show the work, collapsed.** Reasoning steps, tool calls, retrieved chunks
   and search queries are always available and never in the way. Collapsed by
   default, one click to open, and the collapsed header carries a summary
   ("4 tool calls, 2 messages") so the user can decide without opening.
3. **A claim without provenance is a defect.** Any generated statement that
   asserts a fact carries an inline citation to the chunk, row, file, or URL it
   came from, and that citation is clickable through to the source.
4. **Uncertainty is a visual, not a disclaimer.** Confidence is rendered —
   a meter, a band ("High confidence" / "Needs review" / "No signal") — next to
   the recommendation it qualifies. Never a paragraph of hedging prose.
5. **Nothing with a side effect happens without a gate.** Writes, sends,
   purchases, deletes, and external calls go through an approval card that names
   the exact action and its parameters. Reads may proceed freely.
6. **Propose, don't apply.** Agent edits arrive as a reviewable diff — per-row,
   per-line, per-field, each independently acceptable and rejectable. The
   accepted set is applied in one explicit commit.
7. **Output is a starting point.** Every answer ends in affordances: copy,
   retry, edit, rate, follow-up questions, and selection-level actions on any
   passage. Treat generated text as material, never as a final render.

## 2. Token layer

[`tokens.css`](tokens.css) is copy-paste ready for both themes. The shape
matters more than the values:

- **Four surface levels** — `--page` (backdrop), `--canvas` (rail/column),
  `--surface` (card), `--inset` (well inside a card). Agent UIs nest deeply:
  a trace inside a message inside a thread. Without a ladder, everything
  flattens into noise.
- **Three ink levels** — `--ink` for content, `--ink-2` for metadata and labels,
  `--ink-3` for placeholders and not-yet-arrived text. Streaming text starts at
  `--ink-3` and resolves to `--ink`.
- **Hairlines carry structure, shadows only lift overlays.** Every elevation
  token starts with a `0 0 0 1px` ring. Dense agent surfaces have many adjacent
  containers; drop shadows on all of them turns the page to mud.
- **Four semantic hues, each with a tint.** `--accent` (agent/active),
  `--green` (completed/verified), `--orange` (running/needs review),
  `--red` (failed/destructive). The `-tint` variant is the chip fill; the solid
  is the text and icon. On dark, tints are alpha so they compose over any level.
- **Mono means machine-authored.** Code, tool arguments, IDs, elapsed time, and
  token counts use `--font-mono`. Prose is sans. The reader should be able to
  tell what the model wrote from three metres away.

## 3. Motion contract

Exact values live in `tokens.css`. The rules:

| Change | Duration | Easing |
| ------ | -------- | ------ |
| Hover, focus, chip colour | 100–150ms | `--ease-color` |
| Transform, press, toggle | 200ms | `--ease-move` |
| Expand/collapse a trace, list reflow | 300–400ms | `--ease-move` |
| First paint of a card or message | 600ms `fade-up` | `--ease-move` |
| Token arrival while streaming | 0 | none — see below |

- **Animate `opacity` and `transform` only.** Never `height` directly; expand
  with `grid-template-rows: 0fr → 1fr`, which animates on the compositor and
  needs no measured height.
- **Do not animate arriving tokens individually.** A per-token transition at
  60 tokens/s produces a strobe. Animate the *block* on first paint, then let
  text land.
- **Reduced motion keeps the information.** `prefers-reduced-motion` removes
  movement, not signal: the loader keeps its phase label and elapsed counter,
  the trace still expands, streaming still streams.

## 4. Primitive catalogue

Nineteen primitives cover most agent surfaces. Each one is defined by the
states it must handle — that column is where implementations actually fail.

### Agent activity

| Primitive | Job | Must handle |
| --------- | --- | ----------- |
| **Loading state** | The wait itself: phase label, elapsed time, shimmer | pending · running (label changes as phase changes) · slow (>10s, offer cancel) · cancelled |
| **Thinking trace** | Expandable record of steps, reasoning, searches, code | collapsed with summary · streaming (steps append live) · complete · empty (no trace available) |
| **Tool chips** | Tool calls and file edits as compact inline chips | queued · running · succeeded (+ result count) · failed (+ reason, retry) |
| **Task rows** | Long-running agent work as a live list | queued · running (with sub-steps and progress) · completed · failed · needs input · cancelled |
| **Code block** | Machine-written code arriving line by line | streaming (line-numbered, no reflow) · complete · copyable · language-labelled · diff-annotated |

### Answer surfaces

| Primitive | Job | Must handle |
| --------- | --- | ----------- |
| **Streaming text** | The answer, with inline sources and follow-ups | idle · streaming · stopped by user · errored mid-stream (keep partial text) · complete with actions |
| **Chat** | Threaded exchange with reasoning replies and a composer | empty · user turn · agent turn (reasoning collapsed, "for 4s") · error turn with retry · multi-tab context |
| **Context cards** | Retrieved chunks with their source documents | retrieving · N chunks with per-chunk source, type and size · zero-retrieval (say so plainly) · chunk opened to source |
| **Insight cards** | Paged agent findings with live charts | loading · paged (n of m) · chart with scrubbable series · a follow-up question per card |

### Human in the loop

| Primitive | Job | Must handle |
| --------- | --- | ----------- |
| **Approval card** | The question the agent asks before acting | pending decision · options (each one a concrete outcome) · chosen · declined · expired/stale |
| **Recommendation card** | A suggestion with confidence and alternatives | high confidence · needs review · no signal · alternatives expanded · accepted · dismissed |
| **Diff table** | Proposed edits sweeping through tabular data | per-cell before/after · added row · removed row · unchanged · accepted · rejected · partially applied |
| **Fine-tune card** | Inspector where the agent adjusts properties | agent-proposed value vs. user override · reset to proposed · locked property |
| **Selection actions** | Hand a highlighted passage back to the agent | selection active · action menu (explain, improve, shorten, tone, grammar) · rewriting · result preview with accept/reject |

### Input and retrieval

| Primitive | Job | Must handle |
| --------- | --- | ----------- |
| **Prompt bar** | Composer with `@` sources, `/` commands, model picker, dictation | empty · typing · `@` source picker open · `/` command palette open · attachments · recording · submitting · disabled with a stated reason |
| **Search** | Command search with live filtering | idle with suggestions · filtering · no results (with a next action) · recent/pinned |

### Data and navigation

| Primitive | Job | Must handle |
| --------- | --- | ----------- |
| **Records table** | Dense grid with tags, sorting, relationship strength | loading skeleton · sorted · grouped · empty · row selected · agent-modified row flagged |
| **Filter table** | Status chips that reorganise live data | all · per-status counts (counts update live) · empty status · filter cleared |
| **Sidebar nav** | Workspace navigation with quick search and live counts | collapsed/expanded · active route · live badge counts (running tasks, inbox) · quick-search open |

## 5. Streaming mechanics

The single hardest part to get right, and where most implementations break:

- **Reserve the block before the first token.** The answer container gets its
  final width and a minimum height up front. Text growing into a
  correctly-sized box costs no layout shift; text growing into an
  auto-collapsing box reflows the page on every frame.
- **Announce once, not per token.** Wrap the answer in
  `aria-live="polite" aria-atomic="false"` and update a text node. Do **not**
  append announced elements per token — screen readers will read the answer
  dozens of times.
- **Autoscroll is conditional.** Follow the stream only while the user is at the
  bottom. The moment they scroll up, stop, and show a "jump to latest" affordance.
  Yanking the viewport away from someone who is reading is the worst bug in this
  category.
- **Never steal focus mid-stream.** Focus moves on user action only. The
  composer stays focused and usable while the answer streams.
- **A stop control exists and works.** Streaming is cancellable, the partial
  answer is kept, and it is labelled as partial.
- **Errors mid-stream keep what arrived.** Show the partial text, an error row,
  and retry. Never blank out an answer the user was already reading.

## 6. Accessibility contract

- Approval cards and recommendation actions are reachable and operable by
  keyboard, with a visible focus ring. An approval reachable only by mouse is a
  broken gate.
- Status is never colour alone: every state chip pairs its hue with a label or
  icon (running/failed/completed are the ones most often failed).
- Confidence meters carry a text equivalent — `aria-valuenow` plus the band
  name. A bar with no number is decoration.
- Traces and collapsibles use real `<button aria-expanded>`, not a clickable div.
- Contrast: `--ink-2` on `--surface` must clear 4.5:1, `--ink-3` is for
  non-essential text only. Verify both themes.

## 7. Banned

- A spinner with no phase label and no elapsed time.
- A generated fact with no source, or a "sources" affordance that does not link
  to anything.
- Prose hedging ("I think, but I could be wrong…") standing in for a rendered
  confidence signal.
- Any write, send, or delete performed without an approval gate.
- Agent edits applied directly to the user's data with an undo as the only escape.
- Fake determinate progress bars for work of unknown length. Use elapsed time.
- A chat transcript as the only interface to structured work — if the output is
  a table, a diff, or a task list, render it as one.
- Typing-dot animations that convey nothing while a real phase label is available.
- Layout that reflows on every token.
- Emoji as status icons.

## 8. Pre-flight

Before calling an AI-native surface done:

- [ ] Every wait shows a phase and elapsed time
- [ ] Every trace is collapsed by default with a meaningful summary
- [ ] Every asserted fact links to its source
- [ ] Confidence is rendered visually and available as text
- [ ] Every side effect passes through an approval gate that names its parameters
- [ ] Every agent edit is a reviewable, per-item acceptable diff
- [ ] Streaming: reserved block, single live region, conditional autoscroll,
      working stop control, partial text kept on error
- [ ] All nineteen relevant states have a designed empty/failed variant
- [ ] Reduced-motion and both themes verified
- [ ] Keyboard path through approval, retry, and stop

## Reference

Pattern set and token shape derived from the public component gallery
*Beautiful UI — crafted primitives for AI-native interfaces*
(<https://beautiful-ui-five.vercel.app/>, Turbo product design studio),
reviewed 2026-08-11. Guidance and token file here are original; no upstream
code is vendored. Consult the gallery for live, interactive references.
