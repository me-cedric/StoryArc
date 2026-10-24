# Delta section

`openspec validate --strict` reads only the delta headings. Konvoy reads the spec-kit headings. Each `spec.md` keeps both.

1. Keep the spec-kit headings and their text. Do not change or move them.
2. Append `## ADDED Requirements` at the end of `spec.md`.
3. Use `## MODIFIED Requirements` for a requirement that `docs/openspec/specs/<cap>/spec.md` has already. Copy all its scenarios.
4. Write one `### Requirement: <id> <short title>` for each requirement id in the spec. Keep the id, for example `REQ-003`.
5. Write the body in one or two sentences with SHALL or MUST. Restate the spec-kit text. Do not add a requirement.
6. Write one or more `#### Scenario: <name>` blocks under each requirement, with `- GIVEN`, `- WHEN` and `- THEN` lines.
7. Take each scenario from the acceptance criteria or the acceptance scenarios of the spec.
8. If no criterion covers a requirement, do not invent one. Write `- THEN [NEEDS CLARIFICATION: <question>]` and give the question to `grill`.
9. When you change a requirement later, change the spec-kit text and the delta section in the same edit.
10. Run `openspec validate <id> --strict` in the parent folder of `docs/openspec` when the CLI is installed. Else run `ac check --docs`.
