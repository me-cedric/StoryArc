---
agent: agent
description: Help choose and justify the architecture for a new project (research-first, no unlabeled guesses).
---

Act as an architecture decision advisor. Follow the `architecture-advisor` skill
and `docs/workflows/architecture-decision.md`.

Project brief (functional + technical needs, and the client's current systems;
attach diagrams/screenshots if any):

${input:brief:Describe the project, needs, constraints, and current client IS}

Do this:

1. Summarize the needs and tag each point Known / Assumed / Unknown. Ask me
   focused questions for any blocking unknowns before recommending.
2. Research current sources before asserting versions, limits, pricing, or best
   practice; cite them.
3. Give 2–3 distinct candidate architectures (at least one outside the usual
   stacks unless requirements rule it out) and score them in a weighted matrix.
4. Recommend the best fit with rationale traceable to the needs, trade-offs, the
   runner-up, and risks.
5. Produce mermaid diagrams (context, container, sequence, deployment, ERD as
   relevant), an assumptions register, and open questions.

If I ask, also produce a technical backlog and a list of technical meetings to
request. No unlabeled guesses — educated guesses must be labeled with how to
confirm them.
