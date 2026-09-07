// Asserts that this repository's commitlint rules are the rules in force.
//
// Written because `agent-compass` sync created a `commitlint.config.js` on 2026-09-07 beside
// our `commitlint.config.mjs`. The `.js` file wins the cosmiconfig search, and it extends
// only config-conventional. Our `scope-enum` rule went silent: `feat(bogus): x` passed.
// Nothing failed, and no commit would have been rejected again.
//
// This checks the behaviour, not the filename. A future shadow through `.cjs`, a
// `package.json` key or any other search place fails this check the same way.

import { spawnSync } from 'node:child_process'

const ask = (message) =>
  spawnSync('npx', ['--no', '--', 'commitlint'], { input: message, encoding: 'utf8' })

const checks = [
  ['a scope outside the list is refused', 'feat(bogus): a scope this repository does not allow', false],
  ['a scope inside the list is accepted', 'feat(ios): a scope this repository allows', true],
]

let failed = 0
for (const [what, message, shouldPass] of checks) {
  const got = ask(message)
  const passed = got.status === 0
  if (passed !== shouldPass) {
    failed += 1
    console.error(`commitlint-guard: ${what} — expected ${shouldPass ? 'accepted' : 'refused'}, got ${passed ? 'accepted' : 'refused'}`)
    if (got.stdout.trim()) console.error(got.stdout.trim())
  }
}

if (failed) {
  console.error(`
commitlint-guard: this repository's commit rules are not in force.
Look for a second commitlint config beside commitlint.config.mjs. cosmiconfig takes the
first match it finds, and a .js file wins over a .mjs file.`)
  process.exit(1)
}

console.log('commitlint-guard: the scope list is in force.')
