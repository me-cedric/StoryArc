#!/usr/bin/env sh

# Session-start notice only. Never blocks the agent and never changes content.
project_dir=${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}
checker=''

# Where a vendored compass can sit. `AGENT_COMPASS_HOME` wins, so a host that
# vendors somewhere else names it once instead of patching this file.
for candidate in \
  "${AGENT_COMPASS_HOME:-}" \
  "$project_dir/docs/agent-compass" \
  "$project_dir/.agents/agent-compass" \
  "$project_dir/.agent-compass" \
  "$project_dir/vendor/agent-compass"; do
  [ -n "$candidate" ] || continue
  if [ -f "$candidate/scripts/check-update.mjs" ]; then
    checker="$candidate/scripts/check-update.mjs"
    break
  fi
done

# The compass repository itself, where the scripts sit at the root.
if [ -z "$checker" ] &&
  [ -f "$project_dir/scripts/check-update.mjs" ] &&
  [ -f "$project_dir/package.json" ] &&
  grep -q '"name"[[:space:]]*:[[:space:]]*"agent-compass"' "$project_dir/package.json"; then
  checker="$project_dir/scripts/check-update.mjs"
fi

# A host that carries no compass tree has nothing to check. A host that installs
# skill folders alone, and refreshes them from its own tooling, is the case that
# matters. Leaving quietly is correct there, and it is not a failure.

if [ -n "$checker" ] && command -v node >/dev/null 2>&1; then
  node "$checker" "$project_dir" --remote --quiet || true
fi

exit 0
