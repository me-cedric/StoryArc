#!/usr/bin/env node
//
// Verify every .c4 file HERE the way Konvoy loads it — not the way the CLI does.
//
// Konvoy's Models page renders a diagram with:
//
//     const likec4 = await LikeC4.fromSource(previewText);
//     const layouted = await likec4.layoutedModel();
//
// `fromSource` takes ONE file's text. It does not read the directory, so a model
// split across files resolves nothing. Two things make that failure silent:
//
//   1. `fromSource` does not throw on unresolved references. It logs them and
//      returns a model anyway, so Konvoy's try/catch never fires.
//   2. `likec4 validate <dir>` parses the directory as a workspace, so it is
//      green on exactly the layout that Konvoy cannot render.
//
// So this probe asserts both halves:
//
//   * `likec4.hasErrors()` must be false — the check the earlier round skipped
//     by trusting a call that tolerates errors.
//   * every view must actually contain nodes. A view that parses but draws
//     nothing is the exact failure being fixed, and it is invisible to (1).
//
// `view.nodes` and `view.edges` are ZERO-ARGUMENT GENERATOR METHODS, not
// arrays. `view.nodes.length` is the function's arity — it is 0 for a
// known-good file too, which is how an earlier probe passed a broken model.
// The real counts are `[...view.nodes()].length` and `[...view.edges()].length`.
//
// Run:  npx --yes --package likec4@1.59.2 -- node docs/diagrams/check.mjs
// See ./README.md.

import { createRequire } from 'node:module'
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, join, relative, sep } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

// `likec4` is deliberately not a project dependency — nothing in the build
// reads these diagrams. So resolve it from wherever the caller happens to have
// it: next to this script, in the working directory, or in the throwaway
// package `npx --package` puts on PATH as `<somewhere>/node_modules/.bin`.
function resolutionRoots() {
  const roots = [join(here, 'noop.js'), join(process.cwd(), 'noop.js')]
  for (const entry of (process.env.PATH ?? '').split(':')) {
    if (entry.endsWith(`node_modules${sep}.bin`)) {
      roots.push(join(entry, '..', '..', 'noop.js'))
    }
  }
  return roots
}

async function loadLikeC4() {
  for (const from of resolutionRoots()) {
    try {
      const entry = createRequire(from).resolve('likec4')
      return (await import(pathToFileURL(entry).href)).LikeC4
    } catch {
      /* try the next root */
    }
  }
  console.error('Cannot resolve the `likec4` package. Run this script as:')
  console.error('  npx --yes --package likec4@1.59.2 -- node docs/diagrams/check.mjs')
  process.exit(1)
}

const LikeC4 = await loadLikeC4()

/** Every .c4 file under docs/diagrams, at any depth. */
function findC4(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = join(dir, e.name)
    if (e.isDirectory()) return e.name === 'node_modules' ? [] : findC4(p)
    return e.isFile() && e.name.endsWith('.c4') ? [p] : []
  })
}

const files = findC4(here).sort()
if (files.length === 0) {
  console.error('No .c4 files found under', here)
  process.exit(1)
}

let failed = 0

for (const file of files) {
  const name = relative(here, file)
  const likec4 = await LikeC4.fromSource(readFileSync(file, 'utf8'))

  // Half one: the file must resolve on its own.
  if (likec4.hasErrors()) {
    const errors = likec4.getErrors()
    console.error(`FAIL ${name} — ${errors.length} diagnostic(s) from fromSource:`)
    for (const e of errors.slice(0, 10)) {
      console.error(`       ${e.message ?? JSON.stringify(e)}`)
    }
    if (errors.length > 10) console.error(`       … ${errors.length - 10} more`)
    failed++
    continue
  }

  // Half two: every view must actually draw.
  const layouted = await likec4.layoutedModel()
  const views = [...layouted.views()]

  if (views.length === 0) {
    console.error(`FAIL ${name} — parses cleanly but declares no view.`)
    failed++
    continue
  }

  const empty = []
  const counts = views.map((v) => {
    const nodes = [...v.nodes()].length
    const edges = [...v.edges()].length
    if (nodes === 0) empty.push(v.id)
    return `${v.id} (${nodes} nodes, ${edges} edges)`
  })

  if (empty.length > 0) {
    console.error(`FAIL ${name} — view(s) with zero nodes: ${empty.join(', ')}`)
    console.error(`       A view that parses but draws nothing is the bug this file exists to avoid.`)
    failed++
    continue
  }

  console.log(`ok   ${name} — ${counts.join(', ')}`)
}

if (failed > 0) {
  console.error(`\n${failed} of ${files.length} file(s) would not render in Konvoy.`)
  process.exit(1)
}
console.log(`\nAll ${files.length} file(s) load standalone and draw.`)
