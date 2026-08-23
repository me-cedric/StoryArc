---
name: verify-change
description: Change verification gate. Analyzes code changes, checks documentation sync, and assesses change impact. Use when the user mentions change checks, doc sync, code review, pre-commit checks, or diff analysis. Auto-triggers for design-level changes and completed refactors.
license: MIT
compatibility: node>=18
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
argument-hint: [--mode working|staged|committed]
risk_level: medium
writes_files: false
requires_tools: []
---

# ⚖ Verification Gate · Change Verification

## Core principle

```
change = code diff + doc update + recorded rationale
An unexplained change is a hazard; an unrecorded change is a disaster.
Every change is history; every decision leaves a trace.
```

## Automatic analysis

Run the change analyzer script (cross-platform):

```bash
# from the skill directory
node scripts/change_analyzer.cjs                    # analyze working-tree changes (default)
node scripts/change_analyzer.cjs --mode staged      # analyze staged changes
node scripts/change_analyzer.cjs --mode committed   # analyze committed changes
node scripts/change_analyzer.cjs -v                 # verbose mode
node scripts/change_analyzer.cjs --json             # JSON output
```

## Capabilities

### Automated checks

| Check | Description |
|--------|------|
| **File classification** | Identifies code / docs / tests / config files |
| **Module identification** | Identifies the affected modules |
| **Doc sync** | Detects code changes without matching doc updates |
| **Test coverage** | Detects code changes without matching test updates |
| **Impact assessment** | Estimates change size and blast radius |

### Warning conditions

- ⚠️ Code change > 50 lines with no DESIGN.md update
- ⚠️ Code change > 30 lines with no test update
- ⚠️ New files with no README.md update
- ⚠️ Config file changes left unrecorded
- ℹ️ Deleted files need their references confirmed cleaned up

## Pre-change checks

Before modifying any module:

1. **Read README.md** — understand the module's role
2. **Read DESIGN.md** — understand existing decisions
3. **Assess the impact** — what does this change touch
4. **Confirm the rationale** — why change it at all

## Post-change checks

After the code change is done:

### README.md updates

- [ ] Responsibilities changed → update the responsibility description
- [ ] Dependencies changed → update the dependency notes
- [ ] Usage changed → update the example code

### DESIGN.md updates

- [ ] New design decision → record the decision and rationale
- [ ] Existing design modified → record what changed and why
- [ ] New limitation introduced → update known limitations
- [ ] Add a change-history entry

## Change record format

Append to the change history in DESIGN.md:

```markdown
## Change history

### [date] - [change title]

**What changed**: brief summary of the change

**Why**: the reason for the change

**Impact**: affected features/modules

**Decision basis**: why this approach was chosen (when applicable)
```

## Auto-trigger moments

| Scenario | Trigger |
|------|----------|
| Design-level change | Architecture, interface, or data-structure changes |
| Refactor done | When a refactoring task completes |
| Code change > 30 lines | Larger code modifications |
| Pre-commit | Before committing code |

## Verification flow

```
1. Run change_analyzer.cjs
2. Identify changed files and affected modules
3. Check documentation sync status
4. Assess the change impact
5. Emit the change verification report
```

## Report format

```
## Change Verification Report

### Overview
- Files changed: N
- Code lines changed: +X / -Y
- Affected modules: [list]

### Doc sync status
- README.md: ✓ in sync / ⚠️ needs update
- DESIGN.md: ✓ in sync / ⚠️ needs update

### Test coverage
- Test files changed: ✓ yes / ⚠️ no

### Verdict
Ready to commit / complete the docs first
```

---
