---
name: pr-flow
description: Open, update, mark ready or merge a PR or MR with gh or glab: draft, base, labels, reviewer, evidence body. Use when the user asks to open, update or merge one.
risk_level: high
writes_files: false
requires_tools: [git, gh, glab]
---

# pr-flow

Open a PR or MR only when the user asks. Opening one includes the push of its branch.
The project rules in `AGENTS.md` win over the defaults below: base, branch name, labels, language.

## Forge

Use the CLI of the `origin` remote: `gh` for GitHub, `glab` for GitLab (also a self-hosted GitLab). Never a forge MCP.
Check the login first: `gh auth status` or `glab auth status`.

## Before you open

1. `git status --short`. Commit only the files of this change.
2. Branch name: the project pattern, else `<type>/<TICKET>-<short-kebab>`. Rename a tool branch (`claude/…`, `codex/…`) before the first push.
3. Rebase onto the base: `git fetch origin && git rebase origin/<base>`. The guard blocks `git merge` and `git pull` without `--rebase`.
   Push a rebased branch with `git push --force-with-lease origin <branch>`, never `--force`. Ask the user in chat first.
   Claude Code and Copilot also show a permission prompt for it.
4. Review your own change locally with `review` ("Review your own change"). Post nothing. Fix the findings.
5. Run the gates (lint, typecheck, tests) and keep the exact counts for the body.
6. When a `CHANGELOG.md` of a touched app has `## [Unreleased]`, add the entry in this change.

## Base

The base that the project declares. Else `develop` when `git ls-remote --heads origin develop` finds it. Else the default branch:
`gh repo view --json defaultBranchRef -q .defaultBranchRef.name` or `glab repo view -F json` (`.default_branch`).
A feature request onto the release branch is wrong. Ask first.

## Title, labels, people

- Title: `<type>(<scope>): <subject>` in the language of the project's requests, with the ticket key where the project puts it.
- Labels: read them first (`gh label list`, `glab label list`). Use only labels that exist. Never ask about them.
  - One type label from the commit type, for example `feat` → feature, `fix` → bugfix or fix, `docs` → documentation, `ci`/`build` → ci, dependency bumps → dependencies.
  - Each area label whose area the diff touches.
  - Never a label that states a judgement: `breaking-change`, `critical`, `confirmed`. A person sets those.
- Assignee: yourself. Reviewer: at least one. When the user names none, ask, and list the likely ones:
  `gh api 'repos/{owner}/{repo}/contributors' --jq '.[].login'` or `git shortlog -sne --since=6.months -- <changed dirs>`.

## Open as draft

Write the body to `$TMPDIR/pr-<branch>.md`, never into the repository. Follow [references/body.md](references/body.md).

```bash
gh pr create --draft --base <base> --title "<title>" --body-file "$TMPDIR/pr-<branch>.md" \
  --assignee @me --reviewer <login> --label "<label>,<label>"

me=$(glab api user | jq -r .username)
glab mr create --draft --target-branch <base> --title "<title>" --description-file "$TMPDIR/pr-<branch>.md" \
  --assignee "$me" --reviewer <user> --label "<label>,<label>" --yes
```

With `--draft`, the title has no `Draft:` prefix. A GitLab draft MR runs no pipeline. That is expected.
Then move the ticket (see `task-flow`) and give the user the URL.

## Update

- Only add. Never remove a label or an assignee that someone else set.
  - `gh pr edit <n> --add-label <label> --add-assignee @me`
  - `glab mr update <iid> --label <label> --assignee "+$me"`. The `+` is required: a bare assignee replaces the whole list.
- Update the title and the body when a push changes what the branch delivers.
- To answer review threads: fix, push, reply on each thread with the fixing commit, and resolve it.

## Ready and merge

Only after an explicit yes from the user, for each action.

1. Ready: `gh pr ready <n>` or `glab mr update <iid> --ready`. Then add the labels and the assignee again.
2. Rebase onto the base again right before the merge. Merge only with a green pipeline.
3. Merge:
   - `gh pr merge <n> --squash --match-head-commit "$(git rev-parse HEAD)" --delete-branch`
   - `glab mr merge <iid> --squash --sha "$(git rev-parse HEAD)" --remove-source-branch --yes`
4. Check the delivery by tree, because a squash breaks ancestry: `git fetch origin && git diff --stat <branch> origin/<base> -- <touched dirs>` is empty.
5. Move the ticket (see `task-flow`).

Merge a request of someone else only when the user says so for that request.

## Never

- An AI attribution line in a commit, a title, a body or a comment.
- An invented label, count, verdict or file name.
- A merge, a ready switch or a push to the base branch without a yes.
