#!/usr/bin/env node
// openspec-workflows.mjs — generate this repo's OpenSpec agent workflow files
// from the installed CLI's own templates, and fail the build when they drift.
//
// Why this script exists.
//
// `openspec update` is the tool that normally writes these files. It requires the
// OpenSpec root to sit at `<project>/openspec`, and reads the agent directories
// (`.claude/`, `.github/`) from that same `<project>`. This repository keeps the
// root at `docs/openspec` (commit e419dc89) and the agent directories at the
// repository root, so there is no path from which `openspec update` can see
// both: run from `docs/` it finds the root and no agents, run from the root it
// finds the agents and no root.
//
// The visible cost was real. Six of the twelve workflows the CLI ships had never
// been installed here — `verify` (the pre-archive gate) and `continue` (what
// writes the next artifact) among them — so no agent could reach the lifecycle
// gate even when it looked for one. They were not deliberately excluded; the
// installer simply stopped working when the root moved.
//
// So the templates are read from the installed package instead of being copied by
// hand. The content is the vendor's, byte for byte. `--check` runs in `pnpm lint`,
// which means a CLI upgrade that changes a workflow fails the contract gate
// instead of leaving the repository a version behind in silence.

import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const CHECK = args.includes('--check')
const SELF_TEST = args.includes('--self-test')

if (args.includes('--help') || args.includes('-h')) {
  console.log(`Usage: node scripts/openspec-workflows.mjs [--check] [--self-test]

Generate .claude/skills/openspec-*, .claude/commands/opsx/* and
.github/prompts/opsx-* from the installed @fission-ai/openspec templates.

  --check       Fail when a generated file is missing or has drifted.
  --self-test   Check the generator's own assumptions about the package.
`)
  process.exit(0)
}

// The command file name, per workflow module. The CLI keeps this mapping in its
// legacy-cleanup table; it is repeated here because the table is not exported.
const SLUGS = {
  'explore.js': 'explore',
  'new-change.js': 'new',
  'propose.js': 'propose',
  'ff-change.js': 'ff',
  'continue-change.js': 'continue',
  'update-change.js': 'update',
  'apply-change.js': 'apply',
  'verify-change.js': 'verify',
  'sync-specs.js': 'sync',
  'archive-change.js': 'archive',
  'bulk-archive-change.js': 'bulk-archive',
  'onboard.js': 'onboard',
}

// The package does not export `./package.json`, so resolve the install directory
// itself. node_modules holds a symlink into the pnpm store; realpath follows it.
const packageRoot = () => {
  const link = join(ROOT, 'node_modules', '@fission-ai', 'openspec')
  if (!existsSync(link)) {
    console.error('@fission-ai/openspec is not installed. Run: pnpm install')
    process.exit(1)
  }
  return realpathSync(link)
}

const cliVersion = () => JSON.parse(readFileSync(join(packageRoot(), 'package.json'), 'utf8')).version

const workflowDir = () => join(packageRoot(), 'dist', 'core', 'templates', 'workflows')

// Each workflow module exports a skill template and a slash-command template
// under names derived from the workflow, so they are found by shape rather than
// by a second hardcoded table that would rot on the next rename.
const loadTemplates = async () => {
  const dir = workflowDir()
  const out = []
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.js') && SLUGS[f]).sort()) {
    const module = await import(pathToFileURL(join(dir, file)).href)
    let skill = null
    let command = null
    for (const [name, value] of Object.entries(module)) {
      if (typeof value !== 'function') continue
      if (/SkillTemplate$/.test(name)) skill = value()
      else if (/CommandTemplate$/.test(name)) command = value()
    }
    if (!skill || !command) throw new Error(`${file}: expected a skill and a command template, found skill=${!!skill} command=${!!command}`)
    out.push({ file, slug: SLUGS[file], skill, command })
  }
  return out
}

const quote = (value) => `"${String(value).replace(/"/g, '\\"')}"`

const skillFile = (skill, version) => `---
name: ${skill.name}
description: ${skill.description}
allowed-tools: Bash(openspec:*)
license: ${skill.license || 'MIT'}
compatibility: ${skill.compatibility || 'Requires openspec CLI.'}
metadata:
  author: ${skill.metadata?.author || 'openspec'}
  version: ${quote(skill.metadata?.version || '1.0')}
  generatedBy: ${quote(version)}
---

${skill.instructions.trimEnd()}
`

const commandFile = (command) => `---
name: ${quote(command.name)}
description: ${quote(command.description)}
allowed-tools: Bash(openspec:*)
category: ${quote(command.category)}
tags: [${command.tags.map((t) => quote(t)).join(', ')}]
---

${command.content.trimEnd()}
`

// The Copilot prompt carries the same body with the slash form renamed, which is
// what the CLI writes for that tool.
const promptFile = (command, slug) => `---
description: ${quote(command.description)}
---

${command.content.replace(/\/opsx:/g, '/opsx-').trimEnd()}
`

const targets = (entry, version) => [
  [join('.claude', 'skills', entry.skill.name, 'SKILL.md'), skillFile(entry.skill, version)],
  [join('.claude', 'commands', 'opsx', `${entry.slug}.md`), commandFile(entry.command)],
  [join('.github', 'prompts', `opsx-${entry.slug}.prompt.md`), promptFile(entry.command, entry.slug)],
]

const selfTest = async () => {
  const checks = []
  const version = cliVersion()
  checks.push(['the openspec package resolves', existsSync(join(packageRoot(), 'package.json'))])
  checks.push(['the workflow template directory exists', existsSync(workflowDir())])
  const modules = readdirSync(workflowDir()).filter((f) => f.endsWith('.js') && !f.endsWith('.d.ts'))
  const unmapped = modules.filter((f) => !SLUGS[f] && !['store-selection.js', 'feedback.js'].includes(f))
  checks.push([`every workflow module has a slug (unmapped: ${unmapped.join(', ') || 'none'})`, unmapped.length === 0])
  const missing = Object.keys(SLUGS).filter((f) => !modules.includes(f))
  checks.push([`every slug has a module (missing: ${missing.join(', ') || 'none'})`, missing.length === 0])
  const templates = await loadTemplates()
  checks.push([`all ${Object.keys(SLUGS).length} workflows load a skill and a command`, templates.length === Object.keys(SLUGS).length])
  checks.push(['the version is a real semver', /^\d+\.\d+\.\d+/.test(version)])

  for (const [label, ok] of checks) console.log(`${ok ? '✓' : '✗'} ${label}`)
  const failed = checks.filter(([, ok]) => !ok).length
  if (failed) { console.error(`\n✗ openspec-workflows self-test: ${failed} failed.`); process.exit(1) }
  console.log(`\n✓ openspec-workflows self-test: ${checks.length} passed (CLI ${version}).`)
  process.exit(0)
}

if (SELF_TEST) await selfTest()

const version = cliVersion()
const entries = await loadTemplates()
const drift = []
let written = 0

for (const entry of entries) {
  for (const [relative, content] of targets(entry, version)) {
    const path = join(ROOT, relative)
    const current = existsSync(path) ? readFileSync(path, 'utf8') : null
    if (current === content) continue
    if (CHECK) { drift.push(`${relative}: ${current === null ? 'missing' : 'differs from the installed CLI template'}`); continue }
    mkdirSync(dirname(path), { recursive: true })
    writeFileSync(path, content)
    written += 1
  }
}

if (CHECK) {
  if (drift.length) {
    console.error(`✗ OpenSpec workflow files are out of date with @fission-ai/openspec ${version}:\n${drift.map((d) => `  ${d}`).join('\n')}\n\nRun: pnpm openspec:workflows`)
    process.exit(1)
  }
  console.log(`✓ ${entries.length} OpenSpec workflows current with CLI ${version}.`)
} else {
  console.log(`✓ ${entries.length} OpenSpec workflows generated from CLI ${version} (${written} file(s) written).`)
}
