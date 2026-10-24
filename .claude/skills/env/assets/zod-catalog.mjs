#!/usr/bin/env node
// zod-catalog.mjs — write env.catalog.json from a Zod 4 object schema. Copy this file into the project.
// Run it with the project's own zod and tsx:
//   npx tsx scripts/zod-catalog.mjs src/env.ts envSchema [--out env.catalog.json]
// JSON Schema keys map to catalog keys: description, default, examples[0] (example), enum (allowed), pattern.
// The .meta() keys apps, secret and required (an object per env) copy over unchanged.
// "required" for each env starts from the JSON Schema "required" list. A .meta() value overrides it.

import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'
import { z } from 'zod'

const { values, positionals: [file, exportName] } = parseArgs({ allowPositionals: true, options: { out: { type: 'string', default: 'env.catalog.json' } } })
if (!file || !exportName) {
  console.error('Usage: node zod-catalog.mjs <schema module> <export name> [--out env.catalog.json]')
  process.exit(2)
}

const schema = (await import(pathToFileURL(resolve(file)).href))[exportName]
if (!schema) {
  console.error(`error: ${file} has no export named ${exportName}`)
  process.exit(1)
}
const json = z.toJSONSchema(schema, { io: 'input', unrepresentable: 'any' })
if (!json.properties) {
  console.error('error: the schema must be one z.object({ ... }). A merge, an intersection or a $ref is not supported.')
  process.exit(1)
}

const vars = Object.keys(json.properties).sort().map((name) => {
  const p = json.properties[name]
  const base = (json.required ?? []).includes(name)
  return {
    name,
    ...(p.apps && { apps: p.apps }),
    ...(p.description && { description: p.description }),
    ...(p.default !== undefined && { default: String(p.default) }),
    ...(p.examples?.length && { example: String(p.examples[0]) }),
    ...(p.enum ? { allowed: p.enum.map(String) } : p.pattern && { pattern: p.pattern }),
    ...(typeof p.secret === 'boolean' && { secret: p.secret }),
    required: { local: base, ci: base, staging: base, prod: base, ...p.required },
  }
})

writeFileSync(values.out, `${JSON.stringify({ version: 1, vars }, null, 2)}\n`)
console.log(`${values.out}: ${vars.length} variable(s).`)
