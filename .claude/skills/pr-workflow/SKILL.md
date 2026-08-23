---
name: pr-workflow
description: Streamline PR creation, PR reviews, and implementing submitted review fixes with GitHub CLI.
risk_level: medium
writes_files: false
requires_tools: []
---

# PR Workflow

Use when user asks to create a PR, review a PR, submit a GitHub review, or
implement review fixes.

## Create PR

1. Check `git status --short`, branch, remotes, and auth.
2. Default base: `develop`.
3. If reviewer missing, ask for at least one reviewer and list contributors from
   `gh api repos/:owner/:repo/contributors --paginate` or `git shortlog -sne`.
4. Get labels with `gh label list`; use only existing labels.
5. Write detailed PR body: what, why, validation, risks.
6. Create with `gh pr create --base develop --assignee @me --reviewer <login>`.

## Review PR

- Use `pr-review-governance` for the review checklist, summary, and inline
  comment rules.
- Local review: inspect metadata and diff, then report governed findings locally.
- GitHub review: submit `--comment`, `--approve`, or `--request-changes` only
  after the governed checklist is complete.
- Inline comments when exact changed lines matter; summary comment otherwise.

## Implement Review Fixes

1. Read reviews/comments/threads.
2. Verify every requested change against current code.
3. Fix relevant items only.
4. Explain skipped/outdated items.
5. Validate and report.
