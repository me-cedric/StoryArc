# A document for a decider

Read this when the user asks for a document to send to a named decider. The document is a view of the question register, never a fork of it.

## Shape

1. An H1 `# Open questions`, then one bold sentence with both totals: `**<N> actions are blocked. They wait on <M> decisions.**`
2. One paragraph that says the document reads alone: each decision is one question, its options and what it unblocks.
3. The definition of a blocked action: not an unstarted one, but one whose code differs by the choice.
4. `State at <date>.`
5. `## Who must decide`: a table `| Decider | Decisions | Actions unblocked |`, numeric columns right-aligned, a `**Total**` row equal to the sum.
6. `## The decisions, from the most unblocking to the least`: a table `| # | Decision | Decider | Actions |`, sorted by `Actions` descending. The `#` is a rank, not an id.
7. One section per decision, in the same order. Each section holds the question (byte-identical to its table row), one metadata line
   `**Decider:** <role> · **Concerns:** <personas> · **Unblocks:** <N> actions`, three options and the user-visible consequences of the block.

## Rules

- Three options, each a complete configuration that a decider can approve as it is. Exactly one carries `*(recommended)*` at the end of its line. Always recommend.
- No code identifier, file name or ticket id in the text. A decider reads the product, not the repository.
- Every count agrees: the totals sentence, the table rows and the sections.
- A question leaves the register only after its answer is in the decision record. Write the ADR first, then the affected rules, then strike the question.
