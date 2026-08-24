---
id: <project>-commit-convention
trigger: 'when writing a commit message'
confidence: 0.85
domain: git
source: local-repo-analysis
---

# Use Conventional Commits

## Action

Prefix commits with: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`, `build:`, `perf:`, `ci:`

Format: `<type>: <short description in lowercase>`

Examples from the repo:

- `feat: init sftp`
- `fix: resolve fastify duplicate version and ArrayBuffer type errors`
- `test: e2e`
- `build: update to expo 55`

## Evidence

- Analyzed 200 commits
- ~78% follow conventional commit format (155/200)
- Most common: `feat:` (~40%), `fix:` (~30%), `chore:` (~10%), `ci:` (~8%), `refactor:` (~5%)
- Dominant scope: `(api)` (21 uses), then `(mobile)`, `(tests)`, `(ci)`
