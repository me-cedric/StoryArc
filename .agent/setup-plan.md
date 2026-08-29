# Agent Compass Setup Plan

Host: `/Users/me-cedric/Documents/Projects/storyarc`
Mode: `project`

## Answers

```json
{
  "name": "storyarc",
  "scope": "@scope",
  "packageManager": "npm",
  "stacks": [
    "swift-ios"
  ],
  "providers": [
    "claude",
    "codex",
    "gemini",
    "copilot"
  ],
  "useSpecKit": true,
  "codeIntelligence": "none",
  "skillSync": "copy",
  "skillScope": "fit+style"
}
```

## Execution

1. Run `setup-host --strict`.
2. Install Spec Kit bridge files.
3. Sync fit-based skills plus working-style skills using copy.
4. Skip codebase-memory-mcp; it stays an advisory recommendation.
5. Run provider verification, recommendations, quality gates, and dashboard.
