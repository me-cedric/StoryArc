---
name: vuln-triage
description: Triage security findings from osv-scanner, Checkmarx and SonarQube. Merge the SARIF files, rank by CVSS, then fix or suppress with a reason. Use when a scan, a CVE alert or a dependency audit needs action.
risk_level: medium
writes_files: true
requires_tools: [osv-scanner, node]
---

# vuln-triage

Rank the findings first. Fix the highest score first. Never suppress a finding without a reason and a date.

## Collect

1. osv-scanner: `osv-scanner scan source --recursive --config .osv-scanner.toml --format sarif --output-file osv.sarif .`
   - Exit 1 means "findings". It is not a failure of the scanner. Exit 127 or 128 is a failure.
   - Offline: add `--offline-vulnerabilities --download-offline-databases`. Set `OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY` to keep the database between runs.
2. Checkmarx One: `cx results show --scan-id <id> --report-format sarif --output-name cx --output-path .`. Do not start a scan or create a project. Ask the user first.
3. SonarQube has no SARIF export. Use the SonarQube MCP (read-only) to list the issues of type `VULNERABILITY` and the security hotspots.
4. Merge the SARIF files and apply the gate:

```bash
node .agents/skills/vuln-triage/scripts/sarif-merge.mjs --out merged.sarif --fail-at 9 osv.sarif cx.sarif
```

The script keeps one run per tool and drops duplicates. The fingerprint is the rule id, the path and a hash of the snippet,
so a finding keeps its fingerprint when its line moves. Exit 1 lists each finding at or above the `--fail-at` score.

## Rank

| CVSS | Class | Action |
|---|---|---|
| 9.0 or more | critical | Fix now. The CI gate fails. |
| 7.0 to 8.9 | high | Fix in this sprint. |
| 4.0 to 6.9 | medium | Make a ticket. |
| less than 4.0 | low | Fix in a batch upgrade. |

Then adjust the order: a finding in a dev-only dependency or in code that no route reaches goes down. A finding with a known exploit goes up.

## Fix

1. Dependency: upgrade to the first fixed version that osv lists. For a transitive dependency, upgrade the parent first. If no parent release has the fix, add an override (`pnpm.overrides`, npm `overrides`, yarn `resolutions`).
2. Code: make the smallest fix. Add a test that fails before the fix.
3. Install from the lockfile and run the tests.
4. Scan again. The finding must be gone.

## Suppress

Suppress only when no fix exists or the fix breaks the build. Tell the user.

- osv-scanner: add a `[[IgnoredVulns]]` entry in `.osv-scanner.toml` with `id`, `ignoreUntil` and `reason`. Version 2 does not read the old `IgnoreVulns` table.
- Checkmarx or SonarQube: a state change ("not exploitable", "won't fix") is a write in the tool. Ask the user first.

## Report

For each finding, give the id, the package or file, the score, the decision (fixed, suppressed, open) and the command that proves it.

## CI

The `ci-github` and `ci-gitlab` packs run osv-scanner with the offline database and call this script with `--fail-at 9`.
Keep this pack installed when you use them.

## Local SonarQube and Checkmarx

For a SonarQube server on this machine, or a Checkmarx source zip, use the files in `docs/agent-compass/packs/security/extras/`.
Sync does not install them. Copy the scripts into `scripts/` of the project. Ask the user before you run `sonar-setup.sh`: it starts a container.
