---
id: <project>-shared-types
trigger: 'when defining types shared between API, mobile, and backoffice'
confidence: 0.85
domain: architecture
source: local-repo-analysis
---

# Use @scope/shared-types for Cross-App Types

## Action

Types, enums, and interfaces shared across apps must live in `packages/shared-types`:

```typescript
import type {
  ResourceFavorite,
  PaginationParams,
} from '@scope/shared-types';
```

Drizzle `pgEnum` definitions reference constants from shared-types:

```typescript
import { SERVICES, PAYMENT_METHODS } from '@scope/shared-types';
export const serviceEnum = pgEnum('service', SERVICES);
```

Never duplicate types between apps. If a type is needed in more than one app, move it to `@scope/shared-types`.

## Evidence

- `@scope/shared-types` imported across API schema, repositories, services, and mobile app
- Build pipeline: `pnpm build:packages` builds shared-types first
