---
id: <project>-scalar-bruno-gherkin-sync
trigger: 'when modifying API endpoints, DTO fields, payloads, query params, status codes, error responses, or business logic'
confidence: 0.95
domain: api-documentation
source: local-repo-analysis
---

# Keep Scalar/OpenAPI, Bruno, and Gherkin in Sync

When changing API behaviour, update ALL three specification layers in the same task/PR.
Do not defer documentation or test spec updates to a follow-up PR.

## 1. Scalar / OpenAPI (Swagger Decorators)

The project serves interactive API docs at `/openapi` via `@scalar/nestjs-api-reference`
and `@nestjs/swagger`. Every controller endpoint is documented with decorators.

**When you change an endpoint, verify and update:**

- `@ApiOperation({ summary, description })` — reflects the endpoint's purpose
- `@ApiResponse({ status, description, type })` — all possible response codes
- `@ApiQuery({ name, required, ... })` — query parameters
- `@ApiParam({ name, ... })` — path parameters
- `@ApiProperty({ ... })` — DTO field descriptions, examples, required/optional
- `@ApiTags('...')` — tag grouping (maps to `x-tagGroups` in `swagger.ts`)
- `@ApiSecurity('...')` — auth scheme on the controller or method
- `@ApiExcludeEndpoint()` — if removing from public docs

**After decorator changes, verify the app bootstraps without Swagger errors**
(run `pnpm --filter @scope/api typecheck` at minimum).

**New endpoints**: always add the full decorator set. New DTOs: always add `@ApiProperty`
on every field.

**New modules**: register them in `apps/api/src/bootstrap/swagger.ts` under the
`include` array and add their tags to the `x-tagGroups` sections.

File: `apps/api/src/bootstrap/swagger.ts`

## 2. Bruno API Collection

Bruno requests live under `tools/bruno/`, organised by audience:

- `📱 Application/` — mobile app endpoints
- `👤 Backoffice/` — admin panel endpoints
- `🌐 External/` — external service endpoints (Paygate, Globex, Umbrella)
- `🔧 General/` — health, diagnostics

**When you change an endpoint, update the corresponding `.bru` file:**

- URL path, HTTP method, query params — must match the controller route
- Request body schema — match the DTO shape
- Headers — add/remove auth schemes as needed
- `docs { }` block — describe the endpoint's purpose and parameters
- `script:pre-request` / `script:post-response` — update defaults and assertions
- `folder.bru` `seq` ordering — keep logical flow (e.g. init → capture → cancel)

**New endpoints**: create a new `.bru` file in the appropriate folder, add a `folder.bru`
if the folder is new, and follow the existing file naming conventions.

**Deleted endpoints**: remove the `.bru` file and adjust `folder.bru` seq numbers.

## 3. Gherkin Feature Files

Feature files live under `apps/api/features/` and describe business behaviour in
Cucumber/Gherkin format for BDD testing.

**When business logic changes, update the corresponding `.feature` file:**

- Add/update `Scenario` blocks for new behaviour paths
- Adjust `Given` / `When` / `Then` steps to reflect new logic
- Update `Examples` tables if parameterised scenarios exist
- Add new feature files for entirely new business capabilities

**Key modules with existing feature files:**

- `paygate-payments.feature` — capture, callback, deferred auth flows
- `promo-application.feature` — voucher/promo code logic
- `alerts.feature` — alert creation and delivery
- `billing.feature` — invoice and receipt generation
- `street-parking.feature` — session lifecycle
- `active-parking.feature` — resource entry/exit flows
- `resource.service.feature` — resource business logic
- `points-integrity.feature` / `points-admin-adjustment.feature` — loyalty points
- `backoffice-*.feature` — admin operations

## Evidence

- 35+ Gherkin `.feature` files colocated with the API source under `apps/api/features/`
- 195+ Bruno `.bru` request files under `tools/bruno/`, organised by audience
- Scalar API docs at `/openapi` serving all 6 module groups with OAuth2 auth
- AGENTS.md already requires Bruno sync for endpoint changes
