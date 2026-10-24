// openspec.mjs — one resolver for the OpenSpec root, shared by every script that
// reads spec artifacts. A path copied into a second reader is a second root as
// soon as the declaration changes; see the `one-artifact-root` instinct.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

// Checked in order. The declaration in agent-compass.commands.json wins over all
// of them — convention is the fallback, never the authority.
export const CONVENTIONAL_ROOTS = ['openspec', 'docs/openspec', '.openspec']

export const isDir = (path) => { try { return statSync(path).isDirectory() } catch { return false } }

export const dirNames = (path) => {
  try { return readdirSync(path, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort() }
  catch { return [] }
}

export const readText = (path) => { try { return readFileSync(path, 'utf8') } catch { return '' } }

export const readJson = (path) => { try { return JSON.parse(readFileSync(path, 'utf8')) } catch { return null } }

// `changes/` alone is enough to count: a fresh root has no specs yet, and an
// abandoned one keeps an empty `changes/archive/` that still captures the CLI's
// nearest-root resolution.
export const looksLikeRoot = (dir) => isDir(join(dir, 'changes')) || isDir(join(dir, 'specs'))

export const declaredRoot = (root) => {
  const registry = readJson(join(root, 'agent-compass.commands.json'))
  const declared = registry?.paths?.openspec
  return typeof declared === 'string' ? declared.replace(/\/+$/, '') : null
}

// Every root that exists, declaration first. More than one entry is a finding for
// the caller to report, not something this function resolves away.
export const findRoots = (root, override) => {
  if (override) return [override.replace(/\/+$/, '')]
  const found = []
  const declared = declaredRoot(root)
  if (declared && looksLikeRoot(join(root, declared))) found.push(declared)
  for (const candidate of CONVENTIONAL_ROOTS) {
    if (found.includes(candidate)) continue
    if (looksLikeRoot(join(root, candidate))) found.push(candidate)
  }
  return found
}

export const changeConfig = (changeDir) => readText(join(changeDir, '.openspec.yaml'))

export const skipsSpecs = (changeDir) => /^\s*skip_specs\s*:\s*true\s*$/m.test(changeConfig(changeDir))

// A commented-out reason is the point: `skip_specs: true` on its own does not
// tell the next reader a deliberate skip from a forgotten delta.
export const skipReason = (changeDir) =>
  changeConfig(changeDir).split('\n').filter((l) => l.trim().startsWith('#')).join(' ').trim()

export const activeChanges = (openspecDir) =>
  dirNames(join(openspecDir, 'changes')).filter((name) => name !== 'archive')

export const archivedChanges = (openspecDir) => dirNames(join(openspecDir, 'changes', 'archive'))

// Counts every checkbox the change owns, whether the schema puts tasks at the
// change root (spec-driven) or beside each capability spec.
export const taskProgress = (changeDir) => {
  const files = [join(changeDir, 'tasks.md')]
  for (const capability of dirNames(join(changeDir, 'specs'))) files.push(join(changeDir, 'specs', capability, 'tasks.md'))
  let total = 0
  let done = 0
  for (const file of files) {
    for (const line of readText(file).split('\n')) {
      if (/^\s*[-*]\s*\[ \]/.test(line)) total += 1
      else if (/^\s*[-*]\s*\[[xX]\]/.test(line)) { total += 1; done += 1 }
    }
  }
  return { total, done }
}

// The `id` and `generates` of every entry under `artifacts:`, in order.
//
// Read with line regexes, like the config readers further down. This corpus has
// no dependencies, and one YAML parser for a list of two fields is not worth
// being the first.
export const schemaArtifacts = (text) => {
  const out = []
  let inArtifacts = false
  for (const line of text.split('\n')) {
    if (/^artifacts:\s*$/.test(line)) { inArtifacts = true; continue }
    if (!inArtifacts) continue
    // A non-empty line at column zero ends the block.
    if (line.trim() && !/^\s/.test(line)) break
    const id = line.match(/^\s*-\s*id:\s*(\S+)\s*$/)
    if (id) { out.push({ id: unquote(id[1]), generates: '' }); continue }
    const generates = line.match(/^\s*generates:\s*(\S.*?)\s*$/)
    if (generates && out.length) out[out.length - 1].generates = unquote(generates[1])
  }
  // An entry with no `generates` writes no file, so nothing on disk can satisfy
  // it and reporting it `ready` for ever would be worse than not reporting it.
  return out.filter((a) => a.id && a.generates)
}

const unquote = (value) => value.replace(/^["']|["']$/g, '')

// The schema declared under the root, when exactly one is declared.
//
// `<root>/schemas/<name>/schema.yaml` is how a host states a chain other than
// the default one — for example `proposal.md` plus a spec, plan, checklist and
// tasks quartet under `specs/<capability>/`. Without this, the fallback below
// reported `design` and a change-root `tasks.md` missing on every such change,
// for ever — an error no host could ever clear.
//
// Two schemas is not resolved here. `reason` says why nothing came back and the
// caller reports it: guessing which chain is in force is the one answer worse
// than falling back to the default.
export const declaredSchema = (openspecDir) => {
  const dir = join(openspecDir, 'schemas')
  const names = dirNames(dir).filter((name) => existsSync(join(dir, name, 'schema.yaml')))
  if (names.length === 0) return { schema: null, reason: '' }
  if (names.length > 1) return { schema: null, reason: `schemas/ declares ${names.length} schemas: ${names.join(', ')}. Keep one, or the chain gate cannot tell which is in force.` }
  const [name] = names
  const artifacts = schemaArtifacts(readText(join(dir, name, 'schema.yaml')))
  if (artifacts.length === 0) return { schema: null, reason: `schemas/${name}/schema.yaml declares no artifact with a \`generates\` path.` }
  return { schema: { name, artifacts }, reason: '' }
}

// Whether one `generates` pattern is satisfied inside a change directory.
//
// Two shapes, which is every shape a schema uses: a plain relative path, and
// `<dir>/**/<file>` for an artifact written once per capability.
const generated = (changeDir, pattern) => {
  const perCapability = pattern.match(/^(.*)\/\*\*\/([^/]+)$/)
  if (!perCapability) return existsSync(join(changeDir, pattern))
  const [, dir, file] = perCapability
  return dirNames(join(changeDir, dir)).some((name) => existsSync(join(changeDir, dir, name, file)))
}

// Which artifacts the change has on disk. The CLI is authoritative when it is
// installed — see cliStatus in openspec-guard.mjs — so this is the offline
// fallback, and it reports only what it can see rather than inventing a schema
// requirement.
//
// `schema` comes from [declaredSchema]. Without one the chain is the default
// spec-driven quartet, unchanged.
export const fileArtifacts = (changeDir, schema = null) => {
  if (schema) {
    return schema.artifacts.map(({ id, generates }) => {
      if (generated(changeDir, generates)) return { id, status: 'done' }
      // The delta is the one artifact a change may legitimately not have, and
      // `skip_specs` is how it says so. Recognised by where it is written, not
      // by its id: a schema is free to call it `spec` or `specs`.
      if (generates.startsWith('specs/') && skipsSpecs(changeDir)) return { id, status: 'skipped' }
      return { id, status: 'ready' }
    })
  }
  const hasSpecs = dirNames(join(changeDir, 'specs')).length > 0
  return [
    { id: 'proposal', status: existsSync(join(changeDir, 'proposal.md')) ? 'done' : 'ready' },
    { id: 'specs', status: hasSpecs ? 'done' : (skipsSpecs(changeDir) ? 'skipped' : 'ready') },
    { id: 'design', status: existsSync(join(changeDir, 'design.md')) ? 'done' : 'ready' },
    { id: 'tasks', status: existsSync(join(changeDir, 'tasks.md')) ? 'done' : 'ready' },
  ]
}

// Every capability any change has ever carried a delta for, active or archived.
export const touchedCapabilities = (openspecDir) => {
  const changesDir = join(openspecDir, 'changes')
  const touched = new Set()
  const collect = (changeDir) => { for (const capability of dirNames(join(changeDir, 'specs'))) touched.add(capability) }
  for (const name of activeChanges(openspecDir)) collect(join(changesDir, name))
  for (const name of archivedChanges(openspecDir)) collect(join(changesDir, 'archive', name))
  return touched
}

// --- config.yaml, without a YAML dependency ---------------------------------
//
// A list item under `rules:` or `guidance:` that holds an unquoted `": "` makes
// YAML read it as a nested mapping, and the whole document then fails to parse.
// The CLI's answer to a broken config is `No changes exist`, which reads as an
// empty project rather than as a syntax error — so this is worth its own check.
export const configListFaults = (text) => {
  const faults = []
  let inList = false
  let indent = 0
  const lines = text.split('\n')
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i]
    const opener = line.match(/^(\s*)(rules|guidance):\s*$/)
    if (opener) { inList = true; indent = opener[1].length; continue }
    if (!inList) continue
    // A non-empty line at or left of the opener's indent ends the block, unless
    // it is one of the artifact-group keys nested under `rules:`.
    if (line.trim() && !line.startsWith(' '.repeat(indent + 1))) { inList = false; continue }
    const item = line.match(/^\s*-\s+(.*)$/)
    if (!item) continue
    const value = item[1].trim()
    if (/^['"]/.test(value)) continue
    if (/[^\s]:\s/.test(value)) {
      faults.push({ line: i + 1, text: value.slice(0, 90) })
    }
  }
  return faults
}

// The group names under `rules:`, so a rule filed under a misspelt artifact id —
// which is never delivered to any agent — can be reported.
export const configRuleGroups = (text) => {
  const groups = []
  const lines = text.split('\n')
  let inRules = false
  for (const line of lines) {
    if (/^rules:\s*$/.test(line)) { inRules = true; continue }
    if (!inRules) continue
    if (line.trim() && !/^\s/.test(line)) break
    const group = line.match(/^\s{2}([A-Za-z][\w-]*):\s*$/)
    if (group) groups.push(group[1])
  }
  return groups
}
