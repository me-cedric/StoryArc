#!/usr/bin/env node
// openspec-guard.mjs — enforce the OpenSpec change lifecycle in a host project.
//
// Vendored from agent-compass v0.9.6 on 2026-10-24: compass 1.0 removed the guard, and
// `pnpm spec:guard` (in `pnpm lint` and the Contract workflow) still needs it.
//
// `openspec validate` answers "is every file well-formed". It says nothing about
// whether a change has the artifacts its schema requires, whether the task list
// still describes the current proposal, or whether the agent workflows that
// create those artifacts are even installed. A change with a proposal and
// nothing else validates clean. This guard is the missing half.
//
// Checks, each reported with a stable code:
//   root       — exactly one OpenSpec root, resolved and printed
//   config     — config.yaml parses, and every rules group is a real artifact id
//   chain      — every active change has the artifacts its schema requires
//                (from the CLI when installed, else from the schema the root
//                 declares under schemas/, else the default spec-driven chain)
//   deltas     — a change with no delta specs declares skip_specs, with a reason
//   stale      — tasks.md is not older (in git) than the proposal or the specs
//   workflows  — every workflow the installed CLI ships is installed for an agent
//   ready      — a change whose tasks are all ticked is archived, not left open
//   orphans    — every main spec is reachable from a change, active or archived
//
// Grandfathering: `.openspec-guard.json` at the host root records changes that
// predate a gate, each with a reason. A baseline entry that now passes is itself
// a failure, so the file is a ratchet and never a permanent exemption.

import { execFileSync, spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { join, relative } from 'node:path'
import { parseCliArgs, resolveRoot } from './lib/args.mjs'
import {
  activeChanges, configListFaults, configRuleGroups, declaredSchema, dirNames,
  fileArtifacts, findRoots, isDir, readJson, readText, skipReason, skipsSpecs,
  taskProgress, touchedCapabilities,
} from './lib/openspec.mjs'

const { values, positionals } = parseCliArgs({
  name: 'openspec-guard',
  script: 'openspec-guard.mjs',
  summary: `Enforce the OpenSpec change lifecycle: artifact chain, delta discipline,
task freshness, installed agent workflows, and spec traceability.`,
  positionals: [{ name: 'root', required: false }],
  options: {
    openspec: { type: 'string', value: '<dir>', desc: 'OpenSpec root, when the declaration does not name one.' },
    strict: { type: 'boolean', desc: 'Treat warnings as failures.' },
    json: { type: 'boolean', desc: 'Print machine-readable JSON.' },
    'self-test': { type: 'boolean', desc: 'Check the guard against built-in fixtures.' },
  },
})

// Every workflow the OpenSpec CLI ships. An agent that cannot reach one of these
// cannot follow the lifecycle: `verify` is the pre-archive gate and `continue`
// is what creates the next artifact, and both were missing from the host that
// this guard was written for.
const WORKFLOWS = [
  'explore', 'new', 'propose', 'ff', 'continue', 'update',
  'apply', 'verify', 'sync', 'archive', 'bulk-archive', 'onboard',
]

// Where an agent's copy of a workflow lands, per provider. A workflow counts as
// installed when any one of these holds it.
const WORKFLOW_GLOBS = [
  (w) => `.claude/commands/opsx/${w}.md`,
  (w) => `.claude/skills/openspec-${w}/SKILL.md`,
  (w) => `.claude/skills/openspec-${w}-change/SKILL.md`,
  (w) => `.github/prompts/opsx-${w}.prompt.md`,
  (w) => `.cursor/commands/opsx-${w}.md`,
  (w) => `.codex/prompts/openspec-${w}.md`,
  (w) => `.opencode/command/opsx-${w}.md`,
]

// The CLI resolves the *nearest* root from its working directory, so it must run
// from the root's parent. Returns null when the CLI is absent — the guard then
// falls back to reading files, because a missing optional tool never blocks.
const cliStatus = (root, openspecDir, change) => {
  const cwd = join(root, openspecDir, '..')
  const result = spawnSync('npx', ['--no-install', 'openspec', 'status', '--change', change, '--json'], {
    cwd, encoding: 'utf8', timeout: 60_000,
  })
  if (result.status !== 0 || !result.stdout) return null
  try {
    const parsed = JSON.parse(result.stdout)
    return Array.isArray(parsed.artifacts) ? parsed : null
  } catch { return null }
}

// git decides freshness, not mtime: a fresh clone or a worktree gives every file
// the same checkout time, and mtime would report every task list as current.
const lastCommitAt = (root, paths) => {
  const args = ['log', '-1', '--format=%ct', '--']
  for (const path of paths) args.push(path)
  try {
    const out = execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
    return out ? Number(out) : 0
  } catch { return 0 }
}

const installedWorkflows = (root) => WORKFLOWS.filter((w) => WORKFLOW_GLOBS.some((glob) => existsSync(join(root, glob(w)))))

const audit = (root, override) => {
  const findings = []
  const add = (severity, code, message) => findings.push({ severity, code, message })

  const roots = findRoots(root, override)
  if (roots.length === 0) return { root, openspec: null, findings, changes: [] }
  if (roots.length > 1) {
    add('error', 'root', `two OpenSpec roots: ${roots.join(', ')}. The CLI resolves the nearest one, so half the artifacts are invisible from the other. Delete the unused root or name the real one in agent-compass.commands.json.`)
  }

  const openspec = roots[0]
  const openspecDir = join(root, openspec)
  const changesDir = join(openspecDir, 'changes')
  const specsDir = join(openspecDir, 'specs')
  const baseline = readJson(join(root, '.openspec-guard.json'))?.grandfathered || {}
  // Resolved once, before the loop: every change under one root follows the same
  // chain, and reading the schema per change would report the same fault N times.
  const { schema, reason: schemaFault } = declaredSchema(openspecDir)
  if (schemaFault) add('warn', 'config', schemaFault)
  const usedBaseline = new Set()
  const changes = []

  for (const name of activeChanges(openspecDir)) {
    const changeDir = join(changesDir, name)
    const status = cliStatus(root, openspec, name)
      || {
        schemaName: schema
          ? `${schema.name} (from ${openspec}/schemas, CLI unavailable)`
          : 'spec-driven (assumed — CLI unavailable)',
        artifacts: fileArtifacts(changeDir, schema),
      }
    const missing = status.artifacts.filter((a) => a.status !== 'done' && a.status !== 'skipped').map((a) => a.id)
    const progress = taskProgress(changeDir)
    const exempt = Object.prototype.hasOwnProperty.call(baseline, name)
    if (exempt) usedBaseline.add(name)

    changes.push({ name, schema: status.schemaName, missing, progress, artifactIds: status.artifacts.map((a) => a.id) })

    if (missing.length) {
      const detail = `change '${name}' is missing ${missing.join(', ')} — \`openspec validate\` passes it because every file it has is well-formed. Run /opsx:continue, or openspec instructions ${missing[0]} --change "${name}" --json.`
      if (exempt) add('warn', 'chain', `${detail} Grandfathered: ${baseline[name]}`)
      else add('error', 'chain', detail)
    } else if (exempt) {
      add('error', 'baseline', `'${name}' is grandfathered in .openspec-guard.json but now passes. Delete the entry — a baseline is a ratchet, not an exemption.`)
    }

    const hasDeltas = dirNames(join(changeDir, 'specs')).length > 0
    if (!hasDeltas && !skipsSpecs(changeDir)) {
      add('error', 'deltas', `change '${name}' has no delta spec and does not declare skip_specs. Write the delta under changes/${name}/specs/<capability>/spec.md, or declare skip_specs: true in .openspec.yaml with the reason.`)
    } else if (!hasDeltas && skipReason(changeDir).length < 20) {
      add('warn', 'deltas', `change '${name}' declares skip_specs with no written reason. The next reader cannot tell a deliberate skip from a forgotten delta.`)
    }

    const planAt = lastCommitAt(root, [
      relative(root, join(changeDir, 'proposal.md')),
      relative(root, join(changeDir, 'specs')),
      relative(root, join(changeDir, 'design.md')),
    ])
    const tasksAt = lastCommitAt(root, [relative(root, join(changeDir, 'tasks.md'))])
    if (planAt && tasksAt && planAt > tasksAt) {
      add('warn', 'stale', `change '${name}': the proposal, specs or design moved after tasks.md did. Reconcile with /opsx:update before you apply — the task list is describing the older plan.`)
    }

    if (progress.total > 0 && progress.done === progress.total && !missing.length) {
      add('warn', 'ready', `change '${name}' has all ${progress.total} tasks ticked and is still active. Run /opsx:verify, then /opsx:archive.`)
    }
  }

  for (const name of Object.keys(baseline)) {
    if (!usedBaseline.has(name)) add('warn', 'baseline', `.openspec-guard.json grandfathers '${name}', which is no longer an active change. Delete the entry.`)
  }

  const configText = readText(join(openspecDir, 'config.yaml'))
  if (configText) {
    for (const fault of configListFaults(configText)) {
      add('error', 'config', `config.yaml:${fault.line}: an unquoted ": " in a list item makes YAML read it as a mapping, and the whole file then fails to parse. The CLI answers a broken config with "No changes exist", which reads as an empty project. Quote the item: — ${fault.text}`)
    }
    const artifactIds = new Set(changes.flatMap((c) => c.artifactIds || []))
    if (artifactIds.size) {
      for (const group of configRuleGroups(configText)) {
        if (!artifactIds.has(group)) {
          add('warn', 'config', `config.yaml declares rules for '${group}', which is not an artifact in this schema (${[...artifactIds].join(', ')}). Rules under an unknown id are never delivered to any agent.`)
        }
      }
    }
  }

  const installed = installedWorkflows(root)
  const missingWorkflows = WORKFLOWS.filter((w) => !installed.includes(w))
  if (installed.length === 0) {
    add('warn', 'workflows', 'no OpenSpec agent workflow is installed. Run `openspec update` so agents can reach the lifecycle at all.')
  } else if (missingWorkflows.length) {
    add('error', 'workflows', `agents cannot reach ${missingWorkflows.length} workflow(s): ${missingWorkflows.join(', ')}. Run \`openspec update\` — verify is the pre-archive gate and continue is what writes the next artifact.`)
  }

  if (isDir(specsDir)) {
    const touched = touchedCapabilities(openspecDir)
    const orphans = dirNames(specsDir).filter((capability) => !touched.has(capability))
    if (orphans.length) {
      add('warn', 'orphans', `${orphans.length} main spec(s) are named by no change, active or archived: ${orphans.join(', ')}. Their history is unrecoverable — the next behaviour change to one of them should carry a delta.`)
    }
  }

  return { root, openspec, findings, changes }
}

// --- self-test: the guard must fail the shapes it exists to catch -------------

const selfTest = async () => {
  const { mkdtempSync, mkdirSync, writeFileSync, rmSync } = await import('node:fs')
  const { tmpdir } = await import('node:os')
  const dir = mkdtempSync(join(tmpdir(), 'openspec-guard-'))
  const cases = []
  try {
    // A change with a proposal and nothing else: the shape `openspec validate` passes.
    const bare = join(dir, 'openspec', 'changes', 'half-planned')
    mkdirSync(bare, { recursive: true })
    writeFileSync(join(bare, 'proposal.md'), '# Why\n')
    mkdirSync(join(dir, 'openspec', 'specs', 'untouched'), { recursive: true })
    writeFileSync(join(dir, 'openspec', 'specs', 'untouched', 'spec.md'), '# Spec\n')
    let result = audit(dir, 'openspec')
    cases.push(['missing artifacts are an error', result.findings.some((f) => f.code === 'chain' && f.severity === 'error')])
    cases.push(['a change with no delta and no skip_specs is an error', result.findings.some((f) => f.code === 'deltas' && f.severity === 'error')])
    cases.push(['a spec no change names is a warning', result.findings.some((f) => f.code === 'orphans')])
    cases.push(['no installed workflow is a warning', result.findings.some((f) => f.code === 'workflows')])

    // A second root: the trap that makes every change invisible from the wrong cwd.
    mkdirSync(join(dir, 'docs', 'openspec', 'changes', 'archive'), { recursive: true })
    result = audit(dir, null)
    cases.push(['two roots are an error', result.findings.some((f) => f.code === 'root' && f.severity === 'error')])

    // A complete change grandfathered anyway: a stale baseline entry.
    const full = join(dir, 'openspec', 'changes', 'complete')
    mkdirSync(join(full, 'specs', 'thing'), { recursive: true })
    for (const file of ['proposal.md', 'design.md', 'tasks.md']) writeFileSync(join(full, file), '- [x] done\n')
    writeFileSync(join(full, 'specs', 'thing', 'spec.md'), '# Spec\n')
    writeFileSync(join(dir, '.openspec-guard.json'), JSON.stringify({ grandfathered: { complete: 'predates the gate' } }))
    result = audit(dir, 'openspec')
    cases.push(['a baseline entry that now passes is an error', result.findings.some((f) => f.code === 'baseline' && f.severity === 'error')])
    cases.push(['all tasks ticked and still active is a warning', result.findings.some((f) => f.code === 'ready')])

    // A config.yaml whose list item hides an unquoted colon: the break that makes
    // the CLI answer "No changes exist" on a project full of changes.
    writeFileSync(join(dir, 'openspec', 'config.yaml'), [
      'schema: spec-driven',
      'rules:',
      '  proposal:',
      '    - Write [NEEDS CLARIFICATION: question] for an unknown.',
      '  nonsense:',
      '    - A rule filed under an artifact that does not exist.',
    ].join('\n') + '\n')
    result = audit(dir, 'openspec')
    cases.push(['an unquoted colon in a config list item is an error', result.findings.some((f) => f.code === 'config' && f.severity === 'error')])
    cases.push(['a rules group that is not an artifact id is a warning', result.findings.some((f) => f.code === 'config' && f.severity === 'warn')])

    // A root that declares its own chain: no `design.md`, and `tasks.md` beside
    // each capability spec. The default chain reported two artifacts missing on a
    // change that was in fact complete.
    const declared = mkdtempSync(join(tmpdir(), 'openspec-guard-schema-'))
    try {
      const quartet = join(declared, 'openspec', 'changes', 'full-quartet', 'specs', 'thing')
      mkdirSync(quartet, { recursive: true })
      writeFileSync(join(declared, 'openspec', 'changes', 'full-quartet', 'proposal.md'), '# Why\n')
      for (const file of ['spec.md', 'plan.md', 'checklist.md', 'tasks.md']) writeFileSync(join(quartet, file), '- [x] done\n')

      const before = audit(declared, 'openspec')
      cases.push(['the default chain still fails a change with no design.md', before.findings.some((f) => f.code === 'chain' && f.severity === 'error')])

      const schemaDir = join(declared, 'openspec', 'schemas', 'per-capability')
      mkdirSync(schemaDir, { recursive: true })
      writeFileSync(join(schemaDir, 'schema.yaml'), [
        'name: per-capability',
        'version: 1',
        'artifacts:',
        '  - id: proposal',
        '    generates: "proposal.md"',
        '  - id: spec',
        '    generates: "specs/**/spec.md"',
        '  - id: plan',
        '    generates: "specs/**/plan.md"',
        '  - id: checklist',
        '    generates: "specs/**/checklist.md"',
        '  - id: tasks',
        '    generates: "specs/**/tasks.md"',
      ].join('\n') + '\n')

      const after = audit(declared, 'openspec')
      cases.push(['a declared schema decides the chain', !after.findings.some((f) => f.code === 'chain')])
      cases.push(['the declared schema is named in the report', after.changes[0]?.schema.startsWith('per-capability')])

      // Two schemas: reported, and the chain falls back rather than guessing.
      mkdirSync(join(declared, 'openspec', 'schemas', 'other'), { recursive: true })
      writeFileSync(join(declared, 'openspec', 'schemas', 'other', 'schema.yaml'), 'name: other\nartifacts:\n  - id: proposal\n    generates: "proposal.md"\n')
      const ambiguous = audit(declared, 'openspec')
      cases.push(['two declared schemas are a warning', ambiguous.findings.some((f) => f.code === 'config' && f.severity === 'warn')])
    } finally { rmSync(declared, { recursive: true, force: true }) }

    // No root at all: silence, not a failure.
    const empty = mkdtempSync(join(tmpdir(), 'openspec-guard-empty-'))
    try {
      const none = audit(empty, null)
      cases.push(['a project with no OpenSpec root reports nothing', none.openspec === null && none.findings.length === 0])
    } finally { rmSync(empty, { recursive: true, force: true }) }
  } finally { rmSync(dir, { recursive: true, force: true }) }

  const failed = cases.filter(([, ok]) => !ok)
  for (const [label, ok] of cases) console.log(`${ok ? '✓' : '✗'} ${label}`)
  if (failed.length) { console.error(`\n✗ openspec-guard self-test: ${failed.length} of ${cases.length} failed.`); process.exit(1) }
  console.log(`\n✓ openspec-guard self-test: ${cases.length} passed.`)
  process.exit(0)
}

if (values['self-test']) await selfTest()

const ROOT = resolveRoot(positionals)
const report = audit(ROOT, values.openspec)
const errors = report.findings.filter((f) => f.severity === 'error')
const warnings = report.findings.filter((f) => f.severity === 'warn')

if (values.json) {
  console.log(JSON.stringify({ schema: 1, ...report, counts: { errors: errors.length, warnings: warnings.length } }, null, 2))
} else if (!report.openspec) {
  console.log('openspec-guard: no OpenSpec root found. Nothing to check.')
} else {
  console.log(`openspec-guard: root ${report.openspec} — ${report.changes.length} active change(s)`)
  for (const change of report.changes) {
    const state = change.missing.length ? `missing ${change.missing.join(', ')}` : 'planning complete'
    console.log(`  ${change.name}: ${state}${change.progress.total ? ` (${change.progress.done}/${change.progress.total} tasks)` : ''}`)
  }
  for (const finding of report.findings) console.log(`  ${finding.severity === 'error' ? '✗' : '!'} [${finding.code}] ${finding.message}`)
}

if (errors.length || (values.strict && warnings.length)) {
  if (!values.json) console.error(`\n✗ openspec-guard: ${errors.length} error(s), ${warnings.length} warning(s).`)
  process.exit(1)
}
if (!values.json && report.openspec) console.log(`\n✓ openspec-guard passed${warnings.length ? ` with ${warnings.length} warning(s)` : ''}.`)
