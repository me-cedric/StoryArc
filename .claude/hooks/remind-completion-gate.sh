#!/usr/bin/env bash
set -euo pipefail

if [ -f "AGENTS.md" ]; then
  printf 'Completion gate reminder: files changed, commands run, validation results, failures pre-existing/introduced, risks.\n'
fi
