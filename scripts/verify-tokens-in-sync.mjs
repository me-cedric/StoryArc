#!/usr/bin/env node
// verify-tokens-in-sync.mjs — fail when a committed token copy has drifted from
// what the source would generate.
//
// The apps commit their generated tokens so a fresh checkout builds without
// Node. That convenience only holds if the copies are actually current, which
// is what this checks. CI runs it; so does the pre-commit hook.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const DIST = join(ROOT, 'packages', 'design-tokens', 'dist')

const TARGETS = [
  ['swift/StoryArcTokens.swift', 'apps/ios/Packages/StoryArcKit/Sources/DesignSystem/Generated/StoryArcTokens.swift'],
  ['kotlin/StoryArcTokens.kt', 'apps/android/core/designsystem/src/main/kotlin/app/storyarc/core/designsystem/tokens/StoryArcTokens.kt'],
]

const build = spawnSync(
  process.execPath,
  [join(ROOT, 'packages', 'design-tokens', 'scripts', 'build.mjs')],
  { stdio: ['ignore', 'ignore', 'inherit'] },
)
if (build.status !== 0) {
  console.error('Token build failed — fix the tokens before checking sync.')
  process.exit(build.status ?? 1)
}

const stale = TARGETS.filter(([from, to]) => {
  try {
    return readFileSync(join(DIST, from), 'utf8') !== readFileSync(join(ROOT, to), 'utf8')
  } catch {
    return true
  }
})

if (stale.length) {
  console.error('Generated tokens are out of sync with packages/design-tokens:')
  for (const [, to] of stale) console.error(`  ${to}`)
  console.error('\nRun `pnpm tokens:sync` and commit the result with your token change.')
  process.exit(1)
}

console.log('Generated tokens are in sync.')
