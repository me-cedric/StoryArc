// Cuts a release. One command, and everything after it happens in CI.
//
// Usage: pnpm release patch|minor|major   bump, commit, tag, push
//        pnpm release 0.4.0               the same, with the version named outright
//        pnpm release patch --dry         print what it would do and change nothing
//        node scripts/release.mjs --notes 0.4.0   print the en-US notes of one release
//        node scripts/release.mjs --play-notes 0.4.0 12 <dir>   write <dir>/<language>/changelogs/12.txt
//        node scripts/release.mjs --release-body 0.4.0 [<dir>] [--notes-from Unreleased]   print the GitHub release text
//        node scripts/release.mjs --check         fail when a client's version disagrees
//        node scripts/release.mjs --self-test
//
// **What it does here.** Writes the new version into `apps/android/gradle.properties` and
// every other client's version file (`CLIENTS`), files the `## Unreleased` notes of
// `RELEASE_NOTES.md` under the new version, commits that one change, tags it `vX.Y.Z`, and
// pushes the branch and the tag. Nothing is built locally: the signing keys are repository
// secrets and never leave CI.
//
// **What the tag starts.** `.github/workflows/release.yml` fires on `v*`. It builds every
// download (Android, Windows, macOS, Linux), attaches them to a draft GitHub release, and
// gives the Android bundle to Play's internal testing track as a draft. The owner publishes
// the release and rolls out the Play build; `android-promote.yml` moves it between tracks.
//
// **The version code only ever goes up.** Play refuses a code it has already seen, and a
// refusal arrives after the build, so the increment happens here where it is cheap.

import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const GRADLE_PROPERTIES = 'apps/android/gradle.properties'
const PACKAGE_JSON = 'package.json'
const NOTES = 'RELEASE_NOTES.md'
/** Play refuses "What's new" text longer than this, per language. */
const PLAY_NOTES_LIMIT = 500
/** The languages of the Play listing. Each release has notes in each of them. */
export const LANGUAGES = ['en-US', 'de-DE', 'es-ES', 'fr-FR']

/** The body of one heading's section, up to the next heading of the same or a higher level. */
function section(text, level, heading) {
  const lines = text.split('\n')
  const start = lines.findIndex((line) => line.trim() === `${'#'.repeat(level)} ${heading}`)
  if (start < 0) return ''
  const next = new RegExp(`^#{1,${level}} `)
  const end = lines.findIndex((line, index) => index > start && next.test(line))
  return lines.slice(start + 1, end < 0 ? undefined : end).join('\n').trim()
}

/**
 * The notes of one release in one language, trimmed. Empty when there are none.
 *
 * @param {string} text the whole notes file
 * @param {string} heading `Unreleased` or a version such as `0.3.1`
 * @param {string} language one of `LANGUAGES`
 * @returns {string}
 */
export function notesFor(text, heading, language = 'en-US') {
  return section(section(text, 2, heading), 3, language)
}

/** The optional sub-headings under a language. Lines above the first one apply everywhere. */
export const GROUPS = { mobile: 'Phones and tablets', desktop: 'Desktop' }

/** What Play shows when a release changes nothing on a phone or a tablet. */
const PLAY_FALLBACK = {
  'en-US': '- Small improvements.',
  'de-DE': '- Kleine Verbesserungen.',
  'es-ES': '- Pequeñas mejoras.',
  'fr-FR': '- Petites améliorations.',
}

/**
 * One language's notes split into the lines for every platform, for phones and tablets, and for desktops.
 *
 * @param {string} notes the output of `notesFor`
 * @returns {{ shared: string, mobile: string, desktop: string }}
 */
export function notesGroups(notes) {
  return {
    shared: notes.split(/^#### /m)[0].trim(),
    mobile: section(notes, 4, GROUPS.mobile),
    desktop: section(notes, 4, GROUPS.desktop),
  }
}

/** The "What's new" text of Play: every-platform lines and phone lines, never desktop lines. */
export function playNotes(text, heading, language) {
  const { shared, mobile } = notesGroups(notesFor(text, heading, language))
  return [shared, mobile].filter(Boolean).join('\n') || PLAY_FALLBACK[language]
}

/** The files a release carries, in the order the release text lists them. */
export function assets(version) {
  const name = (rest) => `StoryArc-${version}-${rest}`
  return [
    { platform: 'Android', file: name('android.apk') },
    { platform: 'Windows x64', file: name('windows-x64-setup.exe') },
    { platform: 'Windows x64, portable', file: name('windows-x64-portable.zip') },
    { platform: 'Windows ARM64', file: name('windows-arm64-setup.exe') },
    { platform: 'Windows ARM64, portable', file: name('windows-arm64-portable.zip') },
    { platform: 'macOS 26', file: name('macos.dmg') },
    { platform: 'Linux x86_64', file: name('linux-x86_64.flatpak') },
    { platform: 'Linux aarch64', file: name('linux-aarch64.flatpak') },
  ]
}

/**
 * The text of the GitHub release: the en-US notes under one heading for each group that has lines, the
 * downloads, the files a lane failed to make, and how to open a build that has no paid signature.
 *
 * @param {string} text the whole notes file
 * @param {string} version the version name
 * @param {(file: string) => boolean} present whether a download exists; all do when no lane ran
 * @param {string} heading the notes section to read; a rehearsal reads `Unreleased`
 * @returns {string}
 */
export function releaseBody(text, version, present = () => true, heading = version) {
  const { shared, mobile, desktop } = notesGroups(notesFor(text, heading))
  const groups = [
    ['Everywhere', shared],
    [GROUPS.mobile, mobile],
    [GROUPS.desktop, desktop],
  ].filter(([, lines]) => lines)
  const notes =
    groups.length === 1 && groups[0][0] === 'Everywhere'
      ? shared
      : groups.map(([heading, lines]) => `### ${heading}\n\n${lines}`).join('\n\n')
  const files = assets(version)
  const missing = files.filter(({ file }) => !present(file))
  return [
    `## What's new\n\n${notes}`,
    '## Downloads',
    ['| For | File |', '| --- | --- |', ...files.filter(({ file }) => present(file)).map(({ platform, file }) => `| ${platform} | \`${file}\` |`)].join('\n'),
    missing.length ? `**Not in this release:** ${missing.map(({ platform }) => platform).join('; ')}. The build failed; the next release carries it.` : '',
    [
      '## Opening a download',
      '',
      '- **Android:** let your browser or file manager install unknown apps, then open the APK. Play testers get the same build from Play.',
      '- **Windows:** the installer needs no administrator rights. Windows can say "Windows protected your PC": choose **More info**, then **Run anyway**. The portable zip keeps its data in a `data` folder beside `StoryArc.exe`.',
      '- **macOS:** drag StoryArc to Applications. This build is not notarised: open it once, then choose **Open Anyway** in System Settings > Privacy & Security.',
      '- **Linux:** `flatpak install --user` the bundle. Flatpak gets the GNOME runtime from Flathub.',
    ].join('\n'),
  ]
    .filter(Boolean)
    .join('\n\n')
}

/**
 * The notes file with its `## Unreleased` section filed under the new version, and a new
 * empty `## Unreleased` above it.
 *
 * A release with no notes, or with notes Play would refuse after the build, stops here.
 *
 * @param {string} text the whole notes file
 * @param {string} version the new version name
 * @returns {string} the whole notes file, filed
 */
export function fileNotes(text, version) {
  for (const language of LANGUAGES) {
    const notes = notesFor(text, 'Unreleased', language)
    if (!notes) {
      throw new Error(`${NOTES} has no ${language} notes under "## Unreleased". Write what a reader notices, then release.`)
    }
    const play = playNotes(text, 'Unreleased', language)
    if (play.length > PLAY_NOTES_LIMIT) {
      throw new Error(`The ${language} notes for Play are ${play.length} characters and Play takes ${PLAY_NOTES_LIMIT}. Shorten them.`)
    }
  }
  const empty = LANGUAGES.map((language) => `### ${language}\n\n`).join('')
  return text.replace(/^## Unreleased[ \t]*$/m, `## Unreleased\n\n${empty}## ${version}`)
}

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

const WORKSPACE_CRATES = /^(name = "storyarc-(?:core|ffi|linux)"\nversion = ")([^"]+)/gm
const XCODEGEN_NAME = /^(\s*MARKETING_VERSION: ")([^"]+)/m
const XCODEGEN_BUILD = /^(\s*CURRENT_PROJECT_VERSION: ")([^"]+)/m

/**
 * Every other file that carries the version. `gradle.properties` is the source; `expect` says what each
 * file must hold for a version, `read` what it holds, `write` sets it. All three see `{ versionName,
 * versionCode, date }`.
 */
export const CLIENTS = [
  {
    file: PACKAGE_JSON,
    read: (text) => text.match(/^\s*"version":\s*"([^"]+)"/m)?.[1],
    write: (text, v) => text.replace(/^(\s*"version":\s*")[^"]+/m, `$1${v.versionName}`),
  },
  ...['apps/ios/project.yml', 'apps/desktop-macos/project.yml'].map((file) => ({
    file,
    expect: (v) => `${v.versionName} (${v.versionCode})`,
    read: (text) => `${text.match(XCODEGEN_NAME)?.[2]} (${text.match(XCODEGEN_BUILD)?.[2]})`,
    write: (text, v) => text.replace(XCODEGEN_NAME, `$1${v.versionName}`).replace(XCODEGEN_BUILD, `$1${v.versionCode}`),
  })),
  {
    file: 'Cargo.toml',
    read: (text) => text.match(/^\[workspace\.package\]\n(?:(?!\[).*\n)*?version = "([^"]+)"/m)?.[1],
    write: (text, v) => text.replace(/^(\[workspace\.package\]\n(?:(?!\[).*\n)*?version = ")[^"]+/m, `$1${v.versionName}`),
  },
  {
    file: 'Cargo.lock',
    // The three workspace crates. Cargo rewrites them on the next build anyway; writing them here keeps
    // `cargo build --locked` green without a Rust toolchain on the release machine.
    read: (text) => [...new Set([...text.matchAll(WORKSPACE_CRATES)].map((m) => m[2]))].join(', '),
    write: (text, v) => text.replace(WORKSPACE_CRATES, `$1${v.versionName}`),
  },
  {
    file: 'apps/desktop-windows/src/StoryArc.Windows/StoryArc.Windows.csproj',
    read: (text) => text.match(/<Version>([^<]+)<\/Version>/)?.[1],
    write: (text, v) => text.replace(/<Version>[^<]+<\/Version>/, `<Version>${v.versionName}</Version>`),
  },
  {
    file: 'apps/desktop-windows/src/StoryArc.Windows/Package.appxmanifest',
    // The Store requires the fourth part to be 0.
    expect: (v) => `${v.versionName}.0`,
    read: (text) => text.match(/<Identity\b[^>]*?\bVersion="([^"]+)"/)?.[1],
    write: (text, v) => text.replace(/(<Identity\b[^>]*?\bVersion=")[^"]+/, `$1${v.versionName}.0`),
  },
  {
    file: 'apps/desktop-linux/packaging/aur/PKGBUILD',
    // makepkg fetches the tag tarball of pkgver; container-build.sh packs the tree under the Cargo.toml version.
    read: (text) => text.match(/^pkgver=(.+)$/m)?.[1],
    write: (text, v) => text.replace(/^pkgver=.+$/m, `pkgver=${v.versionName}`),
  },
  {
    file: 'apps/desktop-linux/data/com.mecedric.StoryArc.metainfo.xml',
    read: (text) => text.match(/<release version="([^"]+)"/)?.[1],
    write: (text, v) =>
      text.match(/<release version="([^"]+)"/)?.[1] === v.versionName
        ? text
        : text.replace(/^(\s*)<release /m, `$1<release version="${v.versionName}" date="${v.date}"/>\n$1<release `),
  },
]

/**
 * The files whose version disagrees with `gradle.properties`, one line each. Empty when all agree.
 *
 * @param {(file: string) => string} readFile
 * @returns {string[]}
 */
export function disagreements(readFile) {
  const v = readVersion(readFile(GRADLE_PROPERTIES))
  return CLIENTS.flatMap(({ file, read, expect = (x) => x.versionName }) => {
    const found = read(readFile(file))
    return found === expect(v) ? [] : [`${file} has ${found || 'no version'}, and ${GRADLE_PROPERTIES} says ${expect(v)}`]
  })
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

  const block = (line) => LANGUAGES.map((language) => `### ${language}\n\n- ${line} (${language})\n`).join('\n')
  const notes = `# What is new\n\n## Unreleased\n\n${block('A thing a reader sees.')}\n## 0.1.0\n\n${block('The first.')}`
  const filed = fileNotes(notes, '0.2.0')
  assert(LANGUAGES.every((l) => notesFor(filed, 'Unreleased', l) === ''), 'filing leaves an empty Unreleased section')
  assert(filed.includes('## Unreleased\n\n### en-US\n\n### de-DE'), 'filing leaves a heading for each language')
  assert(notesFor(filed, '0.2.0', 'fr-FR') === '- A thing a reader sees. (fr-FR)', 'filing moves the notes under the version')
  assert(notesFor(filed, '0.2.0', 'de-DE') === '- A thing a reader sees. (de-DE)', 'each language reads its own block')
  assert(notesFor(filed, '0.1.0') === '- The first. (en-US)', 'an older section survives')

  const refuses = (text) => {
    try {
      fileNotes(text, '0.2.0')
    } catch {
      return true
    }
    return false
  }
  assert(refuses(`## Unreleased\n\n## 0.1.0\n\n${block('The first.')}`), 'empty notes are refused')
  assert(refuses(notes.replace('### es-ES\n\n- A thing a reader sees. (es-ES)\n', '')), 'a missing language is refused')
  assert(refuses(notes.replace('A thing a reader sees. (de-DE)', 'x'.repeat(PLAY_NOTES_LIMIT))), 'notes over the Play limit are refused')

  const grouped = (language) =>
    `### ${language}\n\n- Everywhere (${language})\n\n#### Phones and tablets\n\n- Phone (${language})\n\n#### Desktop\n\n- Desktop (${language})\n`
  const split = `## 0.3.0\n\n${LANGUAGES.map(grouped).join('\n')}`
  assert(playNotes(split, '0.3.0', 'de-DE') === '- Everywhere (de-DE)\n- Phone (de-DE)', 'Play gets shared and phone lines, never desktop lines')
  const desktopOnly = `## 0.3.0\n\n${LANGUAGES.map((l) => `### ${l}\n\n#### Desktop\n\n- Desktop (${l})\n`).join('\n')}`
  assert(playNotes(desktopOnly, '0.3.0', 'fr-FR') === PLAY_FALLBACK['fr-FR'], 'a desktop-only release still gives Play a line')
  assert(!refuses(desktopOnly.replace('## 0.3.0', '## Unreleased')), 'a desktop-only release is not refused')
  assert(!refuses(split.replace('## 0.3.0', '## Unreleased').replace('Desktop (de-DE)', 'x'.repeat(PLAY_NOTES_LIMIT))), 'desktop lines do not count against Play')

  const body = releaseBody(split, '0.3.0')
  assert(body.includes('### Everywhere\n\n- Everywhere (en-US)') && body.includes('### Desktop\n\n- Desktop (en-US)'), 'the release text has a heading for each group')
  assert(!body.includes('(de-DE)'), 'the release text is English only')
  assert(!body.includes('Not in this release'), 'a full release names nothing as missing')
  const plain = releaseBody(notes, '0.1.0')
  assert(plain.startsWith("## What's new\n\n- The first. (en-US)"), 'shared lines alone need no sub-heading')
  const partial = releaseBody(split, '0.3.0', (file) => !file.includes('windows'))
  assert(partial.includes('**Not in this release:** Windows x64; Windows x64, portable; Windows ARM64; Windows ARM64, portable.'), 'a missing download is named')
  assert(!partial.includes('windows-x64-setup.exe'), 'a missing download is not in the table')

  const files = {
    [GRADLE_PROPERTIES]: 'versionName=0.2.1\nversionCode=6\n',
    [PACKAGE_JSON]: '{\n  "name": "storyarc",\n  "version": "0.1.0",\n  "x": { "version": "9" }\n}\n',
    'apps/ios/project.yml': 'settings:\n    MARKETING_VERSION: "0.1.0"\n    CURRENT_PROJECT_VERSION: "1"\n',
    'apps/desktop-macos/project.yml': 'settings:\n    MARKETING_VERSION: "0.1.0"\n    CURRENT_PROJECT_VERSION: "1"\n',
    'Cargo.toml': '[workspace]\nmembers = []\n\n[workspace.package]\nedition = "2024"\nversion = "0.1.0"\n\n[workspace.dependencies]\nfoo = { version = "1" }\n',
    'Cargo.lock': '[[package]]\nname = "serde"\nversion = "1.0.0"\n\n[[package]]\nname = "storyarc-core"\nversion = "0.1.0"\n\n[[package]]\nname = "storyarc-ffi"\nversion = "0.1.0"\n\n[[package]]\nname = "storyarc-linux"\nversion = "0.1.0"\n',
    'apps/desktop-windows/src/StoryArc.Windows/StoryArc.Windows.csproj': '<PropertyGroup>\n  <Version>0.1.0</Version>\n</PropertyGroup>\n',
    'apps/desktop-windows/src/StoryArc.Windows/Package.appxmanifest': '<Identity\n    Name="x"\n    Version="0.1.0.0" />\n<TargetDeviceFamily MinVersion="10.0.26100.0" />\n',
    'apps/desktop-linux/packaging/aur/PKGBUILD': 'pkgname=storyarc\npkgver=0.1.0\npkgrel=1\n',
    'apps/desktop-linux/data/com.mecedric.StoryArc.metainfo.xml': '  <releases>\n    <release version="0.1.0" date="2026-10-07">\n    </release>\n  </releases>\n',
  }
  assert(disagreements((file) => files[file]).length === CLIENTS.length, 'every client at 0.1.0 disagrees with 0.2.1')
  const v = { versionName: '0.2.1', versionCode: 6, date: '2026-10-21' }
  for (const { file, write } of CLIENTS) files[file] = write(files[file], v)
  assert(disagreements((file) => files[file]).length === 0, 'after writing, every client agrees')
  assert(files[PACKAGE_JSON].includes('"version": "9"'), 'a nested version in package.json is left alone')
  assert(files['Cargo.toml'].includes('foo = { version = "1" }'), 'a dependency version in Cargo.toml is left alone')
  assert(files['Cargo.lock'].includes('name = "serde"\nversion = "1.0.0"'), 'a crates.io crate in Cargo.lock is left alone')
  assert(files['apps/desktop-windows/src/StoryArc.Windows/Package.appxmanifest'].includes('Version="0.2.1.0"'), 'the MSIX version has a fourth part of 0')
  assert(files['apps/desktop-windows/src/StoryArc.Windows/Package.appxmanifest'].includes('MinVersion="10.0.26100.0"'), 'the device family floor is left alone')
  const metainfo = files['apps/desktop-linux/data/com.mecedric.StoryArc.metainfo.xml']
  assert(metainfo.includes('    <release version="0.2.1" date="2026-10-21"/>\n    <release version="0.1.0"'), 'the metainfo gets a new first release, and keeps the old one')
  for (const { file, write } of CLIENTS) files[file] = write(files[file], v)
  assert(files['apps/desktop-linux/data/com.mecedric.StoryArc.metainfo.xml'] === metainfo, 'writing the same version twice adds no second release')
  files['apps/ios/project.yml'] = files['apps/ios/project.yml'].replace('CURRENT_PROJECT_VERSION: "6"', 'CURRENT_PROJECT_VERSION: "5"')
  const one = disagreements((file) => files[file])
  assert(one.length === 1 && one[0].startsWith('apps/ios/project.yml has 0.2.1 (5)'), 'a wrong build number is named by file')

  console.log('release.mjs self-test: all pass')
}

function main() {
  const args = process.argv.slice(2)
  if (args.includes('--self-test')) return selfTest()
  if (args.includes('--notes')) {
    const version = args[args.indexOf('--notes') + 1]
    const notes = notesFor(readFileSync(NOTES, 'utf8'), version)
    if (!notes) throw new Error(`${NOTES} has no en-US notes for ${version}.`)
    return console.log(notes)
  }
  if (args.includes('--play-notes')) {
    const [version, code, dir] = args.slice(args.indexOf('--play-notes') + 1)
    const text = readFileSync(NOTES, 'utf8')
    for (const language of LANGUAGES) {
      if (!notesFor(text, version, language)) throw new Error(`${NOTES} has no ${language} notes for ${version}.`)
      mkdirSync(join(dir, language, 'changelogs'), { recursive: true })
      writeFileSync(join(dir, language, 'changelogs', `${code}.txt`), `${playNotes(text, version, language)}\n`)
    }
    return
  }
  if (args.includes('--release-body')) {
    // With a folder, the downloads that are not in it are named as missing. A rehearsal adds
    // `--notes-from Unreleased`, because the version's own notes are filed only by a release.
    const rest = args.slice(args.indexOf('--release-body') + 1)
    const end = rest.findIndex((arg) => arg.startsWith('--'))
    const [version, dir] = end < 0 ? rest : rest.slice(0, end)
    const heading = args.includes('--notes-from') ? args[args.indexOf('--notes-from') + 1] : version
    const text = readFileSync(NOTES, 'utf8')
    if (!notesFor(text, heading)) throw new Error(`${NOTES} has no en-US notes under "## ${heading}".`)
    const present = dir ? (file) => existsSync(join(dir, file)) : undefined
    return console.log(releaseBody(text, version, present, heading))
  }
  if (args.includes('--check')) {
    const found = disagreements((file) => readFileSync(file, 'utf8'))
    if (found.length) {
      console.error(`The client versions disagree. Run pnpm release, or set them by hand to the gradle.properties values:\n${found.join('\n')}`)
      process.exitCode = 1
    }
    return
  }

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
  const disagree = disagreements((file) => readFileSync(file, 'utf8'))
  if (disagree.length) throw new Error(`The client versions disagree before the release:\n${disagree.join('\n')}`)
  const filedNotes = fileNotes(readFileSync(NOTES, 'utf8'), versionName)

  console.log(`${current.versionName} (${current.versionCode}) -> ${versionName} (${versionCode})`)
  if (dry) {
    for (const language of LANGUAGES) console.log(`${language} (Play):\n${playNotes(filedNotes, versionName, language)}`)
    console.log(`GitHub release:\n${releaseBody(filedNotes, versionName)}`)
    console.log(`Would write ${[GRADLE_PROPERTIES, ...CLIENTS.map(({ file }) => file), NOTES].join(', ')}`)
    console.log(`Would commit, tag ${tag}, and push. Nothing was changed.`)
    return
  }

  const raised = setProperty(setProperty(properties, 'versionName', versionName), 'versionCode', String(versionCode))
  writeFileSync(GRADLE_PROPERTIES, raised)

  const next = { versionName, versionCode, date: new Date().toISOString().slice(0, 10) }
  for (const { file, write } of CLIENTS) writeFileSync(file, write(readFileSync(file, 'utf8'), next))

  writeFileSync(NOTES, filedNotes)

  git('add', GRADLE_PROPERTIES, ...CLIENTS.map(({ file }) => file), NOTES)
  git('commit', '-m', `chore(release): ${tag}`)
  git('tag', '-a', tag, '-m', tag)
  git('push', 'origin', 'HEAD')
  git('push', 'origin', tag)

  console.log(`Pushed ${tag}. Watch it with: gh run watch --exit-status`)
}

main()
