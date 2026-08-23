# Repo Map

Keep this short. Agents read it before broad search.

## Task Routing

Match the task type to the files to read first, so agents stop searching
everything and stop editing the wrong layer. Fill the paths for this repo.

| Task type | Read first | Validate with |
| --------- | ---------- | ------------- |
| API endpoint/payload change | `apps/api/...`, OpenAPI/Bruno/Gherkin sources | `<PM> --filter api test` |
| UI/screen change | `apps/web/...`, design system, Figma context | `<PM> --filter web test` + screenshot |
| Data model/migration | schema + migrations dir, repositories | migration dry-run + repo tests |
| Shared types/package | `packages/...` + every importing consumer | package tests + each consumer |
| Build/CI/deploy | `turbo.json`, CI workflows, Docker | smallest build/bootstrap |
| Security/auth | auth module, guards, `.mcp/tool-contract.md`, secrets policy | security review + tests |
| Docs only | the doc + its index README | docs/link checks |

## Apps And Packages

| Path | Type | Entrypoint | Owner | Validation |
| ---- | ---- | ---------- | ----- | ---------- |
| `<path>` | app/package | `<path>` | team/person | `<PM> ...` |

## Active Surfaces

| Surface | Files | Notes |
| ------- | ----- | ----- |
| API | `apps/api/...` | Public endpoint changes require API contract sync. |
| Web | `apps/web/...` | Match design system and visual regression checks. |

## Generated Or Fragile Files

| Path | Rule |
| ---- | ---- |
| `<path>` | Do not edit directly; change source/template. |

## Dead Zones

Files or folders that look active but are not.

- None known.
