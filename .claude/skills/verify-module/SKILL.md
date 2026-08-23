---
name: verify-module
description: Module completeness gate. Scans the directory structure, detects missing documentation, and verifies code/doc sync. Use when the user mentions module verification, doc checks, structural completeness, README checks, or DESIGN checks. Auto-triggers when a new module is completed.
license: MIT
compatibility: node>=18
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Glob
argument-hint: <module-path>
risk_level: medium
writes_files: false
requires_tools: []
---

# ⚖ Verification Gate · Module Completeness

## Core principle

```
module = code + README.md + DESIGN.md
All three or nothing — an incomplete module does not ship.
```

## Automatic scan

Run the scanner script (cross-platform):

```bash
# from the verify-module directory (recommended)
node scripts/module_scanner.cjs <module-path>
node scripts/module_scanner.cjs <module-path> -v      # verbose mode
node scripts/module_scanner.cjs <module-path> --json  # JSON output
```

## Standard

A complete module must contain:

```
module/
├── README.md      # required — what the module is, why it exists
├── DESIGN.md      # required — design decisions, trade-offs
├── src/           # implementation
└── tests/         # test cases (when applicable)
```

## Checks

### Must exist

| File | Purpose | Consequence when missing |
|------|------|----------|
| `README.md` | Module documentation | 🔴 Blocks delivery |
| `DESIGN.md` | Design-decision record | 🔴 Blocks delivery |

### Should exist

| File/dir | Purpose | Consequence when missing |
|-----------|------|----------|
| `tests/` | Test directory | 🟠 Warning |
| `__init__.py` | Python package marker | 🟡 Notice |
| `.gitignore` | Git ignore config | 🔵 Info |

### README.md must cover

- [ ] **Name and positioning** — one sentence on what it is
- [ ] **Reason to exist** — why this module is needed
- [ ] **Core responsibilities** — what it does and does not do
- [ ] **Dependencies** — what it depends on, what depends on it
- [ ] **Quick start** — smallest working example

### DESIGN.md must cover

- [ ] **Design goals** — the problem being solved, and the non-goals
- [ ] **Options considered** — alternatives and why this one won
- [ ] **Key decisions** — important technical decisions and rationale
- [ ] **Cross-cutting concerns** — security, privacy, observability, cost
- [ ] **Known limitations** — where the current design falls short
- [ ] **Open questions** — decisions that are not yet made
- [ ] **Change history** — record of major changes

This checklist is the section list for a `DESIGN.md`. `gen-docs` scaffolds it and
[documentation.md](../../docs/guidelines/documentation.md) states the rule. Change
all three in the same commit.

## Auto-trigger moments

| Scenario | Trigger |
|------|----------|
| New module | When module creation completes |
| Refactor | When a refactor completes |
| Pre-commit | Before committing code |

## Verification flow

```
1. Run module_scanner.cjs
2. Check the file structure is complete
3. Check every README.md item is covered
4. Check every DESIGN.md item is covered
5. Check code matches what the docs describe
6. Emit the verification report
```

## Report format

```
## Module Verification Report

### Module: <name>

✓ pass | ✗ fail

### File checks
- README.md: ✓ present / ✗ missing
- DESIGN.md: ✓ present / ✗ missing
- tests/: ✓ present / ⚠️ missing

### Content checks
- README completeness: ✓ complete / ⚠️ missing [X, Y, Z]
- DESIGN completeness: ✓ complete / ⚠️ missing [X, Y, Z]

### Verdict
Deliverable / needs completion before delivery
```

## Quick fix

When docs are missing, use the documentation generator:

```bash
/gen-docs <module-path>
```

---
