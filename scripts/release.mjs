// Cuts a release. One command, and everything after it happens in CI.
//
// Usage: pnpm release patch|minor|major   bump, commit, tag, push
//        pnpm release 0.4.0               the same, with the version named outright
//        pnpm release patch --dry         print what it would do and change nothing
//        node scripts/release.mjs --self-test
//
// **What it does here.** Writes the new version into `apps/android/gradle.properties` and
// `package.json`, commits that one change, tags it `vX.Y.Z`, and pushes the branch and the
// tag. Nothing is built locally: the signing keystore and the Play key are repository
// secrets and never leave CI.
//
// **What the tag starts.** `.github/workflows/android-release.yml` fires on `v*`. It builds
// and signs the App Bundle and the APK, publishes a GitHub release carrying the APK, and
// gives the bundle to Play's closed testing track. Promotion to production stays manual:
// that is `android-promote.yml`.
//
// **The version code only ever goes up.** Play refuses a code it has already seen, and a
// refusal arrives after the build, so the increment happens here where it is cheap.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'

const GRADLE_PROPERTIES = 'apps/android/gradle.properties'
const PACKAGE_JSON = 'package.json'

/**
 * The next version name.
 *
 * A bump keyword moves one part and zeroes the parts below it. An explicit `X.Y.Z` is taken
 * as given. Anything else is a typo, and a typo that reached a tag would be a release.
 *
 * @param {string} current a version name such as `0.3.1`
 * @param {string} bump `patch`, `minor`, `major`, or an explicit `X.Y.Z`
 * @returns {string} the new version name
 */
export function nextVersion(current, bump) {
  if (/^\d+\.\d+\.\d+$/.test(bump)) return bump
  const [major, minor, patch] = current.split('.').map(Number)
  if (bump === 'major') return `${major + 1}.0.0`
  if (bump === 'minor') return `${major}.${minor + 1}.0`
  if (bump === 'patch') return `${major}.${minor}.${patch + 1}`
  throw new Error(`Unknown bump "${bump}". Use patch, minor, major, or an explicit X.Y.Z.`)
}

/**
 * A properties file with one key's value replaced.
 *
 * The file is rewritten line by line rather than parsed and re-emitted, so every comment and
 * every unrelated setting survives untouched.
 *
 * @param {string} text the whole file
 * @param {string} key the property to set
 * @param {string} value the value to set it to
 * @returns {string} the whole file, with that one line changed
 */
export function setProperty(text, key, value) {
  const line = new RegExp(`^${key}=.*$`, 'm')
  if (!line.test(text)) throw new Error(`${GRADLE_PROPERTIES} has no ${key} to raise.`)
  return text.replace(line, `${key}=${value}`)
}

/**
 * The version the repository carries now.
 *
 * @param {string} text the whole of `gradle.properties`
 * @returns {{ versionName: string, versionCode: number }}
 */
export function readVersion(text) {
  const name = text.match(/^versionName=(.+)$/m)
  const code = text.match(/^versionCode=(\d+)$/m)
  if (!name || !code) throw new Error(`${GRADLE_PROPERTIES} is missing versionName or versionCode.`)
  return { versionName: name[1].trim(), versionCode: Number(code[1]) }
}

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim()
}

function selfTest() {
  const assert = (condition, what) => {
    if (!condition) throw new Error(`self-test: ${what}`)
  }

  assert(nextVersion('0.3.1', 'patch') === '0.3.2', 'patch raises the last part')
  assert(nextVersion('0.3.1', 'minor') === '0.4.0', 'minor zeroes the patch')
  assert(nextVersion('0.3.1', 'major') === '1.0.0', 'major zeroes both parts below it')
  assert(nextVersion('0.3.1', '2.5.9') === '2.5.9', 'an explicit version is taken as given')
  assert(nextVersion('9.9.9', 'minor') === '9.10.0', 'a part is a number, not a digit')

  let threw = false
  try {
    nextVersion('0.1.0', 'pacth')
  } catch {
    threw = true
  }
  assert(threw, 'a misspelled keyword is refused, not treated as a version')

  const sample = '# a comment\nversionName=0.1.0\nversionCode=1\nother=keep me\n'
  const raised = setProperty(setProperty(sample, 'versionName', '0.2.0'), 'versionCode', '2')
  assert(raised.includes('versionName=0.2.0'), 'the name is replaced')
  assert(raised.includes('versionCode=2'), 'the code is replaced')
  assert(raised.includes('other=keep me'), 'an unrelated property survives')
  assert(raised.includes('# a comment'), 'a comment survives')

  const read = readVersion(raised)
  assert(read.versionName === '0.2.0' && read.versionCode === 2, 'what was written reads back')

  console.log('release.mjs self-test: all pass')
}

function main() {
  const args = process.argv.slice(2)
  if (args.includes('--self-test')) return selfTest()

  const dry = args.includes('--dry')
  const bump = args.find((arg) => !arg.startsWith('--'))
  if (!bump) {
    console.error('Usage: pnpm release patch|minor|major|X.Y.Z [--dry]')
    process.exitCode = 1
    return
  }

  if (!dry && git('status', '--porcelain')) {
    throw new Error('The working tree is dirty. Commit or set aside your work, then release.')
  }

  const properties = readFileSync(GRADLE_PROPERTIES, 'utf8')
  const current = readVersion(properties)
  const versionName = nextVersion(current.versionName, bump)
  const versionCode = current.versionCode + 1
  const tag = `v${versionName}`

  if (git('tag', '--list', tag)) throw new Error(`Tag ${tag} already exists.`)

  console.log(`${current.versionName} (${current.versionCode}) -> ${versionName} (${versionCode})`)
  if (dry) {
    console.log(`Would commit, tag ${tag}, and push. Nothing was changed.`)
    return
  }

  const raised = setProperty(setProperty(properties, 'versionName', versionName), 'versionCode', String(versionCode))
  writeFileSync(GRADLE_PROPERTIES, raised)

  const manifest = readFileSync(PACKAGE_JSON, 'utf8')
  writeFileSync(PACKAGE_JSON, manifest.replace(/^(\s*"version":\s*")[^"]+(")/m, `$1${versionName}$2`))

  git('add', GRADLE_PROPERTIES, PACKAGE_JSON)
  git('commit', '-m', `chore(release): ${tag}`)
  git('tag', '-a', tag, '-m', tag)
  git('push', 'origin', 'HEAD')
  git('push', 'origin', tag)

  console.log(`Pushed ${tag}. Watch it with: gh run watch --exit-status`)
}

main()
