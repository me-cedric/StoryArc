#!/usr/bin/env node
// sarif-merge.mjs — merge SARIF 2.1.0 files into one file with one run per tool, then gate on a CVSS score.
//   node sarif-merge.mjs [--out merged.sarif] [--root .] [--fail-at 9] <file.sarif>...
// Fingerprint: sha256 of the ruleId, the repo-relative path and a hash of the snippet. Without a snippet, the hash
// is of the message, and the start line joins the fingerprint. It goes into partialFingerprints["compass/v1"].
// A result with a known fingerprint is a duplicate.
// Score: "security-severity" in the result properties, else in its rule (the GitHub code scanning convention).
// Exit 0: merged. Exit 1: a finding at or above --fail-at. Exit 2: a usage or input error.
// ponytail: SARIF input only. SonarQube has no SARIF export; triage Sonar issues through the SonarQube MCP.

import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'
import { isAbsolute, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

const USAGE = 'usage: node sarif-merge.mjs [--out merged.sarif] [--root .] [--fail-at 9] <file.sarif>...'
const hash = (text) => createHash('sha256').update(text).digest('hex')
const fail = (message) => {
  console.error(`error: ${message}`)
  process.exit(2)
}

let args
try {
  args = parseArgs({ allowPositionals: true, options: { out: { type: 'string' }, root: { type: 'string', default: '.' }, 'fail-at': { type: 'string' } } })
} catch (err) { fail(`${err.message}\n${USAGE}`) }
const { values, positionals: files } = args
if (!files.length) fail(USAGE)
const failRaw = values['fail-at']
if (failRaw !== undefined && !(/^\d+(\.\d+)?$/.test(failRaw) && Number(failRaw) <= 10)) fail(`--fail-at needs a CVSS score from 0 to 10, not "${failRaw}"`)
const failAt = failRaw === undefined ? null : Number(failRaw)
const root = resolve(values.root)

const decode = (text) => {
  try { return decodeURIComponent(text) } catch { return text }
}

// A repo-relative path with forward slashes. A path outside the root stays absolute. An odd URI keeps its text.
const repoPath = (uri) => {
  let path
  try { path = /^file:/i.test(uri) ? fileURLToPath(uri) : decode(uri) } catch { path = decode(uri.replace(/^file:/i, '')) }
  if (isAbsolute(path)) {
    const rel = relative(root, path)
    if (!rel.startsWith('..') && !isAbsolute(rel)) path = rel
  }
  return path.split(sep).join('/').replace(/^(\.\/)+/, '')
}

// The merged file has no artifacts list, so each location carries its own uri.
const place = (run, location) => {
  const art = location?.physicalLocation?.artifactLocation
  if (!art) return location
  const uri = art.uri ?? run.artifacts?.[art.index]?.location?.uri
  return { ...location, physicalLocation: { ...location.physicalLocation, artifactLocation: uri ? { uri: repoPath(uri) } : {} } }
}

const score = (result, rule) => {
  const value = Number.parseFloat(result.properties?.['security-severity'] ?? rule?.properties?.['security-severity'])
  return Number.isFinite(value) ? value : null
}

const read = (file) => {
  let data
  try { data = JSON.parse(readFileSync(file, 'utf8')) } catch (err) { fail(`${file}: ${err.message}`) }
  if (!Array.isArray(data?.runs)) fail(`${file}: not a SARIF file (no "runs" list)`)
  return data
}

const tools = new Map()
const seen = new Set()
const hits = []
let duplicates = 0

const mergeRun = (run) => {
  const driver = run.tool?.driver ?? {}
  const name = driver.name || 'unknown'
  if (!tools.has(name)) tools.set(name, { driver, rules: new Map(), results: [] })
  const tool = tools.get(name)
  const rules = Array.isArray(driver.rules) ? driver.rules : []
  const byId = new Map(rules.filter((rule) => rule?.id).map((rule) => [rule.id, rule]))
  for (const [id, rule] of byId) if (!tool.rules.has(id)) tool.rules.set(id, rule)

  for (const result of run.results ?? []) {
    const ruleId = result.ruleId ?? result.rule?.id ?? rules[result.ruleIndex ?? result.rule?.index]?.id ?? 'unknown'
    const locations = (result.locations ?? []).map((location) => place(run, location))
    const first = locations[0]?.physicalLocation
    const path = first?.artifactLocation?.uri ?? ''
    const snippet = first?.region?.snippet?.text ?? first?.contextRegion?.snippet?.text
    const line = snippet === undefined ? String(first?.region?.startLine ?? '') : ''
    const text = (snippet ?? result.message?.text ?? '').replace(/\s+/g, ' ').trim()
    const fingerprint = hash(`${ruleId}\0${path}\0${hash(text)}\0${line}`).slice(0, 32)
    if (seen.has(fingerprint)) {
      duplicates++
      continue
    }
    seen.add(fingerprint)
    const { ruleIndex, rule, ...rest } = result
    tool.results.push({ ...rest, ruleId, locations, partialFingerprints: { ...rest.partialFingerprints, 'compass/v1': fingerprint } })
    const value = score(result, byId.get(ruleId) ?? tool.rules.get(ruleId))
    if (failAt !== null && value !== null && value >= failAt) hits.push(`${ruleId} ${path || '-'} ${value}`)
  }
}

// A null result or another bad shape throws. That is an input error (exit 2), not a gate hit.
for (const file of files) {
  for (const run of read(file).runs) {
    try { mergeRun(run) } catch (err) { fail(`${file}: ${err.message}`) }
  }
}

const sarif = {
  $schema: 'https://json.schemastore.org/sarif-2.1.0.json',
  version: '2.1.0',
  runs: [...tools.values()].map(({ driver, rules, results }) => ({ tool: { driver: { ...driver, rules: [...rules.values()] } }, results })),
}
const text = `${JSON.stringify(sarif, null, 2)}\n`
try {
  if (values.out) writeFileSync(values.out, text)
  else process.stdout.write(text)
} catch (err) { fail(`${values.out}: ${err.message}`) }

const counts = [...tools].map(([name, tool]) => `${name}: ${tool.results.length} result(s)`)
console.error(`${counts.join('; ') || 'no runs'}; ${duplicates} duplicate${duplicates === 1 ? '' : 's'} dropped`)
if (hits.length) {
  console.error(`${hits.length} finding(s) at or above CVSS ${failAt}:`)
  for (const hit of hits) console.error(`  ${hit}`)
  process.exit(1)
}
