#!/usr/bin/env node
// sync-tokens.mjs — build the design tokens, then place the generated files
// where each app's build expects them.
//
// The generated sources are committed inside each app so a fresh checkout of
// StoryArc builds in Xcode or Gradle with no Node toolchain present. This
// script is the only thing allowed to write them.

import { spawnSync } from 'node:child_process'
import { copyFileSync, mkdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const DIST = join(ROOT, 'packages', 'design-tokens', 'dist')

const TARGETS = [
  {
    from: join(DIST, 'swift', 'StoryArcTokens.swift'),
    to: join(ROOT, 'apps', 'ios', 'Packages', 'StoryArcKit', 'Sources', 'DesignSystem', 'Generated', 'StoryArcTokens.swift'),
  },
  {
    from: join(DIST, 'kotlin', 'StoryArcTokens.kt'),
    to: join(ROOT, 'apps', 'android', 'core', 'designsystem', 'src', 'main', 'kotlin', 'app', 'storyarc', 'core', 'designsystem', 'tokens', 'StoryArcTokens.kt'),
  },
  // The desktop clients (ADR-0018, task 1.31). The Windows app merges the dictionary in
  // App.xaml; the GTK CSS joins here once the Linux shell loads it.
  {
    from: join(DIST, 'windows', 'StoryArcTokens.xaml'),
    to: join(ROOT, 'apps', 'desktop-windows', 'src', 'StoryArc.Windows', 'Tokens', 'StoryArcTokens.xaml'),
  },
]

const build = spawnSync(process.execPath, [join(ROOT, 'packages', 'design-tokens', 'scripts', 'build.mjs')], { stdio: 'inherit' })
if (build.status !== 0) process.exit(build.status ?? 1)

let changed = 0
for (const { from, to } of TARGETS) {
  const next = readFileSync(from, 'utf8')
  let current = null
  try { current = readFileSync(to, 'utf8') } catch { /* first run */ }
  if (current === next) continue
  mkdirSync(dirname(to), { recursive: true })
  copyFileSync(from, to)
  console.log(`  updated ${to.slice(ROOT.length + 1)}`)
  changed += 1
}

console.log(changed ? `\nSynced ${changed} file(s). Commit them with the token change.` : '\nApps already in sync.')
