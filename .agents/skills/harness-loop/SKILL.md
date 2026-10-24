---
name: harness-loop
description: Run a large goal as a loop with one check, a progress file on disk and a turn cap. Uses the deliver workflow for multi-file work. Use when the user asks you to keep going until a big goal is finished.
risk_level: medium
writes_files: true
requires_tools: [git]
disable-model-invocation: true
---

# harness-loop

## Set up

State these items before you start. Ask only about an item that blocks safe work.

1. Goal: one sentence.
2. Check: one command that proves the goal.
3. Stop condition: the check passes, the turn cap is reached, or a blocker stops the work.
4. Turn cap: 20 turns unless the user says another number. Never raise the cap yourself.
5. Out of scope: what you will not touch.

Write the progress file `.agents/progress/<goal-slug>.md`. It holds the five items above, the done list, the next step and the blockers.
Read it at the start of each turn. A new context resumes from this file.

## Loop

1. Read the repository rules, the project memory and the specs that the goal touches.
2. For work on more than one file, run the `deliver` workflow (`.claude/workflows/deliver.js`) with the goal as args.
   The workflow plans, then splits the work into 2 file groups at most. Workers build. A reviewer checks in a fresh context. Fixes take 2 rounds at most.
   Without workflow support, do the same steps with the `scout`, `worker` and `reviewer` agents.
3. Do one phase in each turn.
4. After each phase, read your diff and run the check.
5. Fix a failure that you introduced before you start the next phase.
6. Write the result in the progress file.
7. At the cap, report "partial" with the blocker. Do not continue.

## Parallel work

1. Run 2 workers at most. Give them files that do not overlap.
2. Before the first edit in a worktree or a new branch, run `git log --oneline main..HEAD` and `git log --oneline HEAD..main`.
3. If the branch is behind and has no commits of its own, run `git merge --ff-only main`.
4. If the branch is behind and has its own commits, tell the parent. Do not rebase.
5. If the user allows commits, commit each finished piece. A session that dies loses uncommitted work.
6. Stay inside the files that your task names.
7. Do not remove a worktree because it looks finished. Wait for the signal of the orchestrator.

## Worktree fence

The desktop app fences each subagent. A hook refuses Edit, Write and git commands that target another worktree.

1. Run the shared steps in the session worktree: merge, screenshots, land.
2. A reviewer of a lane worktree calls `EnterWorktree` with the lane path first.
3. Read a saved subagent report for "the hook refused" notes before you trust it. A refusal appears in the notes, not as a failure.

## Safety

- Do not commit, push, open a PR, deploy, publish, write to production or run a migration on production without approval.
- Use only commands that exist: in `package.json`, in a Makefile, or in the documented command list. Do not invent one.
- Prefer a narrow fix to a broad rewrite.

## Handoff

Give the goal, the files changed, each command with its result, the risks and the next step.
