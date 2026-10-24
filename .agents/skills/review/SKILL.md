---
name: review
description: Review a change, a branch or PR/MR N on spec and standards. For PR/MR N, show a recap, then post the summary, inline comments and verdict. Use before done.
risk_level: medium
writes_files: false
requires_tools: [git]
---

# review

Report correctness defects and requirement gaps only. Skip style preferences.

- Spec axis: does the change do what the spec, issue or ticket asks?
- Standards axis: does the change follow the repository rules (`AGENTS.md`, module docs, lint config)?

## Forge

Use the CLI of the `origin` remote: `gh` for GitHub, `glab` for GitLab (also a self-hosted GitLab). Never a forge MCP for these calls.

| Step | GitHub | GitLab |
|---|---|---|
| Metadata | `gh pr view <n> --json title,body,author,baseRefName,headRefName,headRefOid,labels` | `glab mr view <iid> -F json` |
| Head and base | `gh api repos/{owner}/{repo}/pulls/<n>` (`.base.sha`, `.head.sha`) | `glab api "projects/:id/merge_requests/<iid>"` (`.diff_refs`) |
| Diff | `gh pr diff <n>` | `git diff <base_sha> <head_sha>` |
| Threads | `gh api repos/{owner}/{repo}/pulls/<n>/comments` | `glab api "projects/:id/merge_requests/<iid>/discussions"` |
| Other open requests | `gh pr list` | `glab mr list` |

## Steps

1. Fix the scope. For PR/MR N, review the head SHA that the forge reports, not a local branch. For a branch, ask for the base when it is missing.
2. Freeze the acceptance criteria before you read the diff: the ticket (see `task-flow`), the specs in `docs/openspec`, the PR or MR text. If there is no source, ask. Do not invent criteria.
3. Read each reference at the base commit: `git show '<base>:<path>'`. A change that edits its own spec cannot judge itself.
4. Read the existing threads. Check for commits pushed after the request opened: late commits are often unannounced scope.
5. Start the `reviewer` agent in a fresh context. Give it the base, the head, the criteria, the standards sources and the style contract. Do not give it your reasoning.
6. Open the cited `path:line` of each finding before you accept it. A finding is a claim.
7. Write the report. See [references/report.md](references/report.md).

For your own change, fix the real findings, run the checks again and ask `reviewer` again. Do at most 2 fix rounds.

## What to check

Spec axis: mark each criterion `OK`, `KO` or `not verified`. Look both ways: a criterion that the code does not meet, and code that no criterion asks for.

Standards axis:

- Module boundaries, logger, input validation, error handling, repository conventions.
- A test for each new branch, guard and error path. Docs that follow the behavior.
- Conventional commits with the ticket key.

Always check:

- Scope: the diff matches the ticket title. Call out a feature that also changes an auth path, or weakens a lint or CI gate.
- The target branch follows the branch strategy. A feature request onto the release branch is `P1`.
- Overlap with the other open requests: the same route, shared type or migration, also with no path overlap.
- A renamed route, selector or label that breaks an existing test. A passing test that asserts a removed behavior.
- A test that guards prose: it proves that the text exists, not that it is true.
- A UI change: run `ui-conformance`. A red pipeline: run `ci-triage` before you call the code broken.

## Evidence

- "verified" only for what you ran: a command, a test, a rendered page.
- "code matches" for what you read. "stated" for the request text, the ticket and a green CI badge.
- An axis that you could not run is `not verified`, with the reason. Tier is not severity: `P0 [code matches]` is valid.

## Review your own change

Do this before you open a PR or MR, and before you report a change done. Post nothing: this review is local.
Typecheck and mocked tests cannot see these failures:

1. The app does not boot: a new provider with a dependency that its module cannot resolve.
2. The validation pipe does not run, so a DTO is decoration. Unknown keys must be stripped and server-owned fields must not be settable.
3. The response leaks an internal column.
4. A by-id path takes its scope from the body, not from the token.

Run the full build and the whole test suite, not only the new tests. Fix the findings. State what you chose not to fix, and why.

## Post a review of PR/MR N

"Review PR N" or "review MR N" asks for a posted review. "Review locally", a branch or your own change posts nothing.

1. Write `$TMPDIR/review-<n>.json`, outside the repository: `{ "summary": "<report>", "verdict": "<v>", "comments": [{ "path", "line", "body" }] }`.
   One comment for each finding on a changed line, 2 to 4 sentences: what is wrong, why it matters here, the fix.
2. Verdict: `request_changes` with a `P0` or `P1`; `approve` when no `P0` or `P1` remains and the checks have evidence; `comment` otherwise.
3. Show the recap, and wait for an explicit yes:
   `node .agents/skills/review/scripts/post-review.mjs --pr <n> --review "$TMPDIR/review-<n>.json" --dry`
4. After the yes, run the same command without `--dry`. The script posts the summary, then the inline comments, then the verdict.
   It moves a comment outside the diff into the summary, skips a duplicate of an existing thread, and turns the verdict into a comment on your own request.
5. Report the URL and each line that the script did not anchor. On GitLab without "request changes", the summary carries the verdict.

## Forge actions

- Merge only when the user says so in chat. Authorship, a green pipeline and an earlier review give no right to merge.
- Add no AI attribution line to a summary or a comment.
- To open or update a PR or MR, use `pr-flow`.
- To act on posted review comments: read every thread, check each request against the current code, fix the valid ones, explain each skip, and reply on the thread.
