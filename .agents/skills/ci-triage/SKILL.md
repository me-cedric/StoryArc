---
name: ci-triage
description: Triage a red CI job: read the log, classify it as flaky, environment or real, reproduce it, fix small and rerun. Use when a pipeline or check is red.
risk_level: low
writes_files: false
requires_tools: [gh, glab]
---

# ci-triage

A red pipeline is not always a code defect. Read the failed job, not the pipeline color.

## Steps

1. Get the failed job log:
   - GitHub: `gh run list --limit 5`, then `gh run view <run-id> --log-failed`.
   - GitLab: `glab ci status`, then `glab ci trace <job>`.
2. Read the log from the first error, not from the last line.
3. Note which jobs pass. If tests, lint and typecheck pass, suspect the environment or a gate that runs over the whole commit range.
4. A commit linter runs over every commit of the branch. One inherited commit with a bad subject reddens each build. Reword or squash that commit. Do not change code.
5. Classify the failure, using the table.
6. Reproduce it locally with the command that the CI file runs, the same tool versions and a lockfile install.
7. If you cannot reproduce it, say so. Name the likely difference: OS, env var, test order, time zone, network, cache.
8. Make the smallest fix for one cause. Do not skip, weaken or delete a test. Do not relax a gate.
9. Run the checks locally. Push only when the user asks.
10. Rerun the failed job: `gh run rerun <run-id> --failed`, or `glab ci retry <job>`. Confirm that it passes.

## Classes

| Class | Sign | Action |
|---|---|---|
| Flaky | Passes on a rerun. The cause is timing, order or shared state. | Find the cause. Rerun once to confirm. Do not hide it with a retry. |
| Environment | The runner, network, cache, secret, quota or tool version failed. Unrelated commits fail the same way. | Fix the CI config or tell the owner. Do not change code. |
| Real | It fails on the same commit locally, and a change in the diff explains it. | Fix the code. |

## Packaging builds

An exit code is not a build result for an installer, an image, an APK or a binary.

1. The artifact exists at the path that the build declares.
2. It comes from this run. Compare it with a marker file that you create when the run starts. Do not compare it with a source file time.
3. It opens: `unzip -t`, `tar -tf`, `docker image inspect`, `hdiutil verify`.
4. A zero exit can ship the previous build, because a bundler may reuse an existing output directory. Delete the output before the build.
5. A non-zero exit can still leave a good artifact, because packaging runs last. Look before you call the build failed.
6. Clean the leftover state at the start of each build, not after a failure.

## Report

Give the job, the class, the cause, the fix and the rerun result. Say what you did not verify.
