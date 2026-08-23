---
name: verify-quality
description: Code quality gate. Detects complexity, duplicated code, naming-convention violations, function length, and other quality metrics. Use when the user mentions code quality, complexity checks, code smells, refactoring suggestions, lint checks, or coding standards. Auto-triggers for complex modules and completed refactors.
license: MIT
compatibility: node>=18
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Glob
argument-hint: <scan-path>
risk_level: medium
writes_files: false
requires_tools: []
---

# ⚖ Verification Gate · Code Quality

## Core principle

```
code quality = readability + maintainability + testability
Bad code is technical debt; debt cracks the foundation.
Complexity is where bugs breed.
```

## Automatic check

Run the quality checker script (cross-platform):

```bash
# from the skill directory
node scripts/quality_checker.cjs <scan-path>
node scripts/quality_checker.cjs <scan-path> -v      # verbose mode
node scripts/quality_checker.cjs <scan-path> --json  # JSON output
```

## Metrics

### Complexity metrics

| Metric | Threshold | Consequence when exceeded |
|------|------|----------|
| **Cyclomatic complexity** | ≤ 10 | 🟠 Warning — split the function |
| **Function length** | ≤ 50 lines | 🟠 Warning — split the function |
| **File length** | ≤ 500 lines | 🟡 Notice — consider splitting |
| **Parameter count** | ≤ 5 | 🟠 Warning — consider an options object |
| **Nesting depth** | ≤ 4 | 🟠 Warning — refactor |
| **Line length** | ≤ 120 | 🔵 Info |

### Naming conventions

| Kind | Convention | Example |
|------|------|------|
| **Class names** | PascalCase | `UserService`, `HttpClient` |
| **Function names** | snake_case | `get_user`, `process_data` |
| **Constants** | UPPER_SNAKE | `MAX_RETRY`, `DEFAULT_TIMEOUT` |
| **Variables** | snake_case | `user_id`, `total_count` |

(Adapt to the host language's idiom — e.g. camelCase functions/variables in
TypeScript; the host project's convention wins.)

### Code smells

| Smell | Description | Severity |
|------|------|--------|
| Duplicated code | Similar blocks > 10 lines | 🟠 High |
| Long parameter list | More than 5 parameters | 🟡 Medium |
| Magic numbers | Unnamed constants | 🟡 Medium |
| Dead code | Unused functions/variables | 🔵 Low |
| Commented-out code | Disabled code blocks | 🔵 Low |

## Auto-trigger moments

| Scenario | Trigger |
|------|----------|
| Complex module | More than 200 lines of code |
| Refactor done | When a refactoring task completes |
| Code review | During PR/MR review |
| Pre-commit | Before committing code |

## Verification flow

```
1. Scan the code files
2. Compute complexity metrics
3. Detect code smells
4. Check naming conventions
5. Emit the quality report
```

## Report format

```
## Code Quality Report

✓ pass | ✗ fail

### Complexity metrics
- Average function complexity: N
- Functions over threshold: N
- Largest file (lines): N

### Code smells
- 🟠 High: N
- 🟡 Medium: N
- 🔵 Low: N

### Issue list

| File | Line | Kind | Severity | Description |
|------|------|------|--------|------|
| ... | ... | ... | ... | ... |

### Verdict
Deliverable / refactor before delivery
```

## Refactoring guidance

### Reduce complexity

```python
# 🔴 High complexity — deep nesting
def process(data):
    if condition1:
        if condition2:
            if condition3:
                # deeply nested logic
                pass

# ✅ Low complexity — guard clauses
def process(data):
    if not condition1:
        return
    if not condition2:
        return
    if not condition3:
        return
    # main logic
```

### Remove duplication

```python
# 🔴 Duplicated code
def func1():
    # 10 identical lines
    pass

def func2():
    # 10 identical lines
    pass

# ✅ Extract the shared function
def common_logic():
    # shared logic
    pass

def func1():
    common_logic()

def func2():
    common_logic()
```

---
