---
id: <project>-testing-pattern
trigger: 'when writing unit tests for NestJS services'
confidence: 0.9
domain: testing
source: local-repo-analysis
---

# Use jest-mock-extended with NestJS Test Module

## Action

Unit tests use `jest-mock-extended` for type-safe mocks and NestJS `Test.createTestingModule()`:

```typescript
import { Test, type TestingModule } from '@nestjs/testing';
import { mock } from 'jest-mock-extended';

// Mock transactional decorator
jest.mock('@nestjs-cls/transactional', () => ({
  Transactional: () => jest.fn(),
}));

describe('FooService', () => {
  let service: FooService;
  const mockRepo = mock<FooRepository>();
  const mockLogger = mock<OtelLogger>();

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FooService,
        { provide: FooRepository, useValue: mockRepo },
        { provide: OtelLogger, useValue: mockLogger },
      ],
    }).compile();

    service = module.get(FooService);
  });

  it('should do something', async () => {
    mockRepo.findOne.mockResolvedValue(fixture);
    const result = await service.getOne('id');
    expect(result).toEqual(expected);
  });
});
```

Key patterns:

- Always mock `@nestjs-cls/transactional` `Transactional` decorator
- Define typed test fixtures as constants at the top of the file
- Colocate `.spec.ts` next to source files

## Evidence

- 51 spec files use this pattern
- `jest-mock-extended` used consistently for DI mocking
- `@nestjs-cls/transactional` mock present in tests using `@Transactional()`
