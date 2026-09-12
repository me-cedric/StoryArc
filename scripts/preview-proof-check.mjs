#!/usr/bin/env node
/**
 * A change a user can see, pushed with a `#Preview` as its only evidence.
 *
 * **The rule exists and nothing executes it.** `AGENTS.md` §6 says a SwiftUI `#Preview` and
 * a Compose `@Preview` are development aids, not proof, because neither exercises real data,
 * real insets, real system materials or a real Dynamic Type setting. The capability spec says
 * the same in `docs/openspec/specs/native-experience/spec.md`, scenario *Preview is not
 * proof*. Both are prose. A branch that redraws a screen and captures nothing passes every
 * gate in `pnpm lint` today.
 *
 * So this refuses one shape: **a commit in this branch changes drawing code, and the branch
 * adds no frame under `docs/designs/screenshots/`.**
 *
 * **This gate refuses a push, so it is built to stay quiet.** A false refusal costs more than
 * a missed frame, because the next person it blocks deletes it. Four decisions follow from
 * that, and each one loses cases on purpose:
 *
 * 1. **Added lines only.** A hunk that only removes lines does not count. A removal changes a
 *    screen too, but reading the intent of a removal from a diff is guesswork.
 * 2. **The declaration is the unit, not the file.** An added line counts only inside a Swift
 *    declaration that conforms to `View` or `ViewModifier` or returns `some View`, or inside a
 *    Kotlin `@Composable`. 161 of 822 Swift files and 157 of 770 Kotlin files hold such a
 *    declaration today, and a plain type beside one is still not drawing code. Test sources
 *    never count.
 * 3. **Preview blocks are cut out.** An added line inside a `#Preview`, a `PreviewProvider` or
 *    an `@Preview` function is not a drawing change — adding a preview is the one edit this
 *    gate must never ask for a screenshot. The repository holds one `@Preview` today, in
 *    `LibraryScreen.kt`, and no `#Preview` at all.
 * 4. **Drawing is read from commits; a frame is read from commits and from the working tree.**
 *    Both sides of the refusal are lenient. `pnpm lint` runs at pre-push, where the whole
 *    change is committed, so the strict reading buys nothing and would refuse work in
 *    progress that cannot yet carry a commit message.
 *
 * **A frame is an image file under `docs/designs/screenshots/`.** That tree holds 1000 `.png`
 * files and 53 `.md` files today, so a README added beside the frames is not a frame.
 *
 * **Two exceptions, and no third.** `AGENTS.md` §6 names them: code behind a flag that nothing
 * renders yet, and a pure refactor whose screenshots are byte-identical. It also says the
 * handoff must name which one applies. Name it in a commit message, the way
 * `scripts/commitlint-guard.mjs` treats commit text as the place a claim is recorded:
 *
 *     Visual-proof: flag        code behind a flag that nothing renders yet
 *     Visual-proof: identical   a pure refactor whose screenshots are byte-identical
 *
 * Any other word after `Visual-proof:` is refused, because a third exception does not exist.
 *
 * **The gate passes when it cannot see the branch.** No `main`, no merge base, or no git at
 * all means no verdict, not a failure. This runs inside `pnpm lint`, which runs at pre-push,
 * where the branch is whole. It is deliberately not a `Contract` workflow step: that job
 * checks out at depth 1, where no merge base exists and this would report nothing. Give that
 * job `fetch-depth: 0` before adding a step for it.
 *
 * Usage:
 *   node scripts/preview-proof-check.mjs              check this branch against `main`
 *   node scripts/preview-proof-check.mjs --self-test  prove the refusal and both exceptions
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const FRAMES = 'docs/designs/screenshots/'
const IMAGE = /\.(png|jpe?g|heic|webp|gif)$/i
const MARKER = /^[ \t]*Visual-proof:[ \t]*(\w+)/im
const EXCEPTIONS = {
  flag: 'code behind a flag that nothing renders yet',
  identical: 'a pure refactor whose screenshots are byte-identical',
}

/** A test source. Drawing code in a test draws for the test, and no reader sees it. */
const TEST_PATH = /(^|\/)(Tests?|UITests|androidTest|test)\/|Tests?\.(swift|kt)$/

/**
 * The head of a declaration that draws.
 *
 * Swift declares it by conformance or by return type; Compose declares it by annotation. A
 * rule extracted out of a view into a plain type in the same file is not drawing code, which
 * is why the file is not the unit — `ServerShelfCardView.swift` grew a 26-line `enum` in
 * commit `eaebe94f` and a whole-file test would have asked that refactor for a screenshot.
 */
const DRAWS = {
  swift: /:\s*View\b|:\s*ViewModifier\b|\bsome View\b|^\s*extension View\b/,
  kotlin: /^\s*@Composable\b/,
}

/** The head of a preview block. Swift has two forms; Compose stacks its annotations. */
const PREVIEW = {
  swift: /^\s*#Preview\b|:\s*PreviewProvider\b/,
  kotlin: /^\s*@[A-Za-z]*Preview[A-Za-z]*\b/,
}

/** A line that changes nothing a reader sees. */
const NOISE = {
  swift: /^\s*(\/\/|\/\*|\*|(@\w+\s+)?(public |internal |private |package )?import\b)|^\s*$/,
  kotlin: /^\s*(\/\/|\/\*|\*|import\b|package\b)|^\s*$/,
}

/** The language a path is judged as, or `null` when the path is not drawing code at all. */
export function language(path) {
  if (TEST_PATH.test(path)) return null
  if (/^apps\/ios\/.+\.swift$/.test(path)) return 'swift'
  if (/^apps\/android\/.+\.kt$/.test(path)) return 'kotlin'
  return null
}

/**
 * The added lines of every file in a unified diff, with their line numbers in the new file.
 *
 * `-U0` gives no context lines, so a `+` line is the only thing that advances the counter.
 * The new path comes from `+++ b/<path>`, which follows a rename to where the file now is.
 */
export function parseDiff(text) {
  const files = []
  let current = null
  let line = 0
  for (const row of text.split('\n')) {
    if (row.startsWith('diff --git ')) {
      current = null
    } else if (row.startsWith('+++ ')) {
      const path = row.slice(4).trim()
      current = path === '/dev/null' ? null : { path: path.replace(/^b\//, ''), added: [] }
      if (current) files.push(current)
    } else if (row.startsWith('--- ')) {
      continue
    } else if (row.startsWith('@@')) {
      const found = /^@@ -\d+(?:,\d+)? \+(\d+)/.exec(row)
      line = found ? Number(found[1]) : 0
    } else if (!current) {
      continue
    } else if (row.startsWith('+')) {
      current.added.push({ line, text: row.slice(1) })
      line += 1
    } else if (row.startsWith(' ')) {
      line += 1
    }
  }
  return files
}

/**
 * The line span of every block a marker opens, 1-based and inclusive.
 *
 * A marker inside a block already found is skipped, so `var body: some View` inside
 * `struct X: View` yields one span rather than two nested ones. A comment is never a marker:
 * `LibraryStates.swift` discusses `#Preview` in its own documentation.
 *
 * The braces are counted without reading the language. A brace inside a string would extend a
 * block to the end of the file, which makes the gate quieter about that file rather than
 * louder — the direction a refusing gate should fail in.
 */
export function ranges(content, kind, marker) {
  const lines = content.split('\n')
  const found = []
  for (let i = 0; i < lines.length; i += 1) {
    if (NOISE[kind].test(lines[i]) || !marker[kind].test(lines[i])) continue
    if (found.length && i + 1 <= found[found.length - 1][1]) continue
    found.push(blockRange(lines, i))
  }
  return found
}

export const previewRanges = (content, kind) => ranges(content, kind, PREVIEW)
export const drawingRanges = (content, kind) => ranges(content, kind, DRAWS)

/** From a marker line to the close of the block it opens. */
function blockRange(lines, start) {
  let depth = 0
  let opened = false
  for (let i = start; i < lines.length; i += 1) {
    // A Compose preview stacks `@Preview`, `@Composable` and the signature before its brace.
    if (!opened && i - start > 6) return [start + 1, start + 1]
    for (const character of lines[i]) {
      if (character === '{') {
        depth += 1
        opened = true
      } else if (character === '}') {
        depth -= 1
      }
    }
    if (opened && depth <= 0) return [start + 1, i + 1]
  }
  return [start + 1, lines.length]
}

/** The added lines of one file that a reader could see, or an empty list. */
export function drawnLines(file, kind, content) {
  const draws = drawingRanges(content, kind)
  if (!draws.length) return []
  const previews = previewRanges(content, kind)
  const inside = (spans, line) => spans.some(([from, to]) => line >= from && line <= to)
  return file.added.filter(
    ({ line, text }) =>
      !NOISE[kind].test(text) && inside(draws, line) && !inside(previews, line),
  )
}

/** The exception a commit message claims, or `null`. An unknown word is not an exception. */
export function claimedException(messages) {
  for (const message of messages) {
    const found = MARKER.exec(message)
    if (found && Object.hasOwn(EXCEPTIONS, found[1])) return found[1]
  }
  return null
}

/**
 * The verdict, from text alone.
 *
 * `contentOf` reads a changed file as the branch left it. Everything else is diff text, path
 * strings and commit messages, so the self-test drives the same function the check does.
 */
export function analyse({ diffText, contentOf, framePaths, messages }) {
  const drawing = []
  for (const file of parseDiff(diffText)) {
    const kind = language(file.path)
    if (!kind) continue
    const content = contentOf(file.path)
    if (content === null) continue
    const lines = drawnLines(file, kind, content)
    if (lines.length) drawing.push({ path: file.path, kind, lines: lines.length })
  }
  const frames = framePaths.filter((path) => path.startsWith(FRAMES) && IMAGE.test(path))
  const exception = claimedException(messages)
  const ok = drawing.length === 0 || frames.length > 0 || exception !== null
  return { drawing, frames, exception, ok }
}

const git = (args, cwd = ROOT) => execFileSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 64e6 })

/** The commit this branch left `main` at, or `null` when that cannot be established. */
function mergeBase() {
  for (const branch of ['main', 'origin/main']) {
    try {
      return git(['merge-base', 'HEAD', branch]).trim()
    } catch {
      continue
    }
  }
  return null
}

/**
 * Every frame the branch adds: committed since the merge base, staged, or still untracked.
 *
 * A frame still in the working tree counts. The drawing half of the verdict is read from
 * commits only, so a person who has captured the evidence is never asked to commit it first.
 * Only a deletion is dropped here; a replaced baseline is evidence too.
 */
function addedFrames(base, cwd = ROOT) {
  const committed = git(['diff', '--name-only', '--diff-filter=A', '-M', base, 'HEAD', '--', FRAMES], cwd)
  // `-uall` names each new file. The default names the directory, and a directory is not a
  // frame — which is how the first capture of a sweep, still untracked, went uncounted.
  const working = git(['status', '--porcelain', '-uall', '--', FRAMES], cwd)
    .split('\n')
    .filter((row) => row.length > 3 && !row.slice(0, 2).includes('D'))
    .map((row) => row.slice(3))
  return [...committed.split('\n'), ...working].map((path) => path.trim()).filter(Boolean)
}

function check() {
  const base = mergeBase()
  if (!base) {
    console.log('preview-proof: no merge base with `main` here, so there is nothing to compare.')
    return 0
  }
  const head = git(['rev-parse', 'HEAD']).trim()
  if (head === base) {
    console.log('preview-proof: this branch adds no commit to `main`.')
    return 0
  }
  const diffText = git([
    'diff', '-U0', '--no-color', '-M', '--diff-filter=ACMR', base, 'HEAD',
    '--', 'apps/ios', 'apps/android',
  ])
  const messages = git(['log', '--format=%B%x00', `${base}..HEAD`]).split('\0')
  const result = analyse({
    diffText,
    contentOf: (path) => {
      try {
        return git(['show', `HEAD:${path}`])
      } catch {
        return null
      }
    },
    framePaths: addedFrames(base),
    messages,
  })
  return report(result)
}

function report({ drawing, frames, exception, ok }) {
  console.log(
    `preview-proof: ${drawing.length} drawing change(s), ${frames.length} new frame(s)`
      + `${exception ? `, exception claimed: ${exception}` : ''}.`,
  )
  if (ok) return 0
  console.error('\npreview-proof: this branch redraws a screen and captures nothing.\n')
  for (const file of drawing) {
    const what = file.kind === 'swift' ? 'SwiftUI' : 'Compose'
    console.error(`  ${file.path}\n      ${file.lines} added line(s) of ${what} drawing code, outside any preview.`)
  }
  console.error(`
A \`#Preview\` and a \`@Preview\` are development aids, not proof. Neither exercises real
data, real insets, real system materials or a real Dynamic Type setting.

Capture from a booted simulator or emulator, in light and dark, at the default and the
largest text size. Put the frames in \`${FRAMES}<topic>-<yyyy-mm-dd>/\`:

  xcrun simctl io booted screenshot shot.png
  pnpm capture:android --list
  pnpm capture:android <route> --out shot.png --dark --font-scale 2.0

AGENTS.md §6 allows two exceptions, and no third. Name the one that applies in a commit
message on this branch:

  Visual-proof: flag        ${EXCEPTIONS.flag}
  Visual-proof: identical   ${EXCEPTIONS.identical}
`)
  return 1
}

/**
 * A frame captured and not yet committed, read out of a real repository.
 *
 * The one case text alone cannot prove, and it broke once: `git status --porcelain` names the
 * *directory* of a new capture set, and a directory is not a frame, so a person who had done
 * the work was refused. The test builds a repository, drops a file in and asks for the list.
 */
function untrackedFrameCase() {
  const dir = mkdtempSync(join(tmpdir(), 'preview-proof-'))
  try {
    git(['init', '-q'], dir)
    git(['config', 'user.email', 'gate@storyarc.invalid'], dir)
    git(['config', 'user.name', 'preview-proof self-test'], dir)
    writeFileSync(join(dir, 'seed.txt'), 'a repository needs one commit to have a base\n')
    git(['add', '-A'], dir)
    git(['commit', '-qm', 'seed'], dir)
    const base = git(['rev-parse', 'HEAD'], dir).trim()
    const frame = `${FRAMES}shelf-2026-09-12/light.png`
    mkdirSync(join(dir, FRAMES, 'shelf-2026-09-12'), { recursive: true })
    writeFileSync(join(dir, frame), 'the bytes do not matter here')
    return ['an untracked frame counts, although git names only its directory by default',
      addedFrames(base, dir).includes(frame)]
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

function selfTest() {
  // Line numbers matter: every case below adds a line at a stated line of one of these two.
  const view = [
    'import SwiftUI', //                             1
    '', //                                           2
    'struct LibraryScreen: View {', //                3
    '    var body: some View {', //                   4
    '        Text("shelf")', //                       5
    '    }', //                                       6
    '}', //                                           7
    '', //                                            8
    '#Preview("shelf") {', //                         9
    '    LibraryScreen()', //                        10
    '}', //                                          11
    '', //                                           12
    'struct LibraryScreen_Previews: PreviewProvider {', // 13
    '    static var previews: some View {', //        14
    '        LibraryScreen()', //                     15
    '    }', //                                       16
    '}', //                                          17
    '', //                                           18
    'enum ShelfTiles {', //                          19
    '    static func of(items: [Int]) -> [Int] {', // 20
    '        items.sorted()', //                     21
    '    }', //                                       22
    '}', //                                          23
    '', //                                           24
  ].join('\n')
  const composable = [
    'package app.storyarc.feature.library', //        1
    '', //                                            2
    '@Composable', //                                 3
    'fun LibraryScreen() {', //                       4
    '    Text("shelf")', //                           5
    '}', //                                           6
    '', //                                            7
    '@Preview(name = "Empty library")', //            8
    '@Composable', //                                 9
    'private fun LibraryScreenPreview() {', //       10
    '    LibraryScreen()', //                        11
    '}', //                                          12
    '', //                                           13
  ].join('\n')
  const helper = ['import Foundation', '', 'struct Shelf {', '    let id: String', '}', ''].join('\n')

  const diff = (path, start, lines) =>
    `diff --git a/${path} b/${path}\n--- a/${path}\n+++ b/${path}\n`
      + `@@ -${start},0 +${start},${lines.length} @@\n`
      + lines.map((line) => `+${line}`).join('\n')
      + '\n'

  const SWIFT = 'apps/ios/App/LibraryScreen.swift'
  const KOTLIN = 'apps/android/feature/library/src/main/kotlin/app/storyarc/LibraryScreen.kt'
  const contents = {
    [SWIFT]: view,
    [KOTLIN]: composable,
    'apps/ios/App/Shelf.swift': helper,
    'apps/ios/Packages/StoryArcKit/Tests/LibraryFeatureTests/ShelfTests.swift': view,
  }
  const run = ({ diffText, framePaths = [], messages = [''] }) =>
    analyse({
      diffText,
      contentOf: (path) => contents[path] ?? null,
      framePaths,
      messages,
    })

  const swiftBody = diff(SWIFT, 5, ['        Text("count")'])
  const kotlinBody = diff(KOTLIN, 5, ['    Text("count")'])
  const cases = []

  let got = run({ diffText: swiftBody })
  cases.push(['a SwiftUI body change with no frame is refused', !got.ok && got.drawing.length === 1])

  got = run({ diffText: kotlinBody })
  cases.push(['a Compose body change with no frame is refused', !got.ok && got.drawing[0].kind === 'kotlin'])

  got = run({ diffText: swiftBody, framePaths: [`${FRAMES}shelf-2026-09-12/light.png`] })
  cases.push(['a frame satisfies the gate', got.ok && got.frames.length === 1])

  got = run({ diffText: swiftBody, framePaths: [`${FRAMES}shelf-2026-09-12/README.md`] })
  cases.push(['a markdown file beside the frames is not a frame', !got.ok])

  got = run({ diffText: swiftBody, framePaths: ['docs/designs/other/light.png'] })
  cases.push(['an image outside the frame tree is not a frame', !got.ok])

  got = run({ diffText: swiftBody, messages: ['feat(ios): a shelf\n\nVisual-proof: flag\n'] })
  cases.push(['the flag exception is honoured', got.ok && got.exception === 'flag'])

  got = run({ diffText: swiftBody, messages: ['refactor(ios): a shelf\n\nVisual-proof: identical\n'] })
  cases.push(['the byte-identical exception is honoured', got.ok && got.exception === 'identical'])

  got = run({ diffText: swiftBody, messages: ['feat(ios): a shelf\n\nVisual-proof: later\n'] })
  cases.push(['a word that is not one of the two exceptions is refused', !got.ok && got.exception === null])

  got = run({ diffText: swiftBody, messages: ['feat(ios): a shelf', 'chore(ios): tidy\n\nVisual-proof: flag\n'] })
  cases.push(['any commit on the branch may carry the marker', got.ok])

  got = run({ diffText: diff(SWIFT, 10, ['    LibraryScreen(state: .empty)']) })
  cases.push(['a line added inside a `#Preview` block is not a drawing change', got.ok])

  got = run({ diffText: diff(SWIFT, 15, ['        LibraryScreen(state: .empty)']) })
  cases.push(['a `PreviewProvider` body is a preview, although it returns `some View`', got.ok])

  got = run({ diffText: diff(SWIFT, 21, ['        items.reversed()']) })
  cases.push(['a plain type beside a view, in the same file, is not a drawing change', got.ok])

  got = run({ diffText: diff(KOTLIN, 11, ['    LibraryScreen(state = Empty)']) })
  cases.push(['a line added inside an `@Preview` function is not a drawing change', got.ok])

  got = run({ diffText: diff(SWIFT, 5, ['        // the shelf, counted', '']) })
  cases.push(['a comment and a blank line are not a drawing change', got.ok])

  got = run({ diffText: diff(SWIFT, 1, ['import SwiftUI']) })
  cases.push(['an import is not a drawing change', got.ok])

  got = run({ diffText: diff('apps/ios/App/Shelf.swift', 4, ['    let title: String']) })
  cases.push(['a Swift file that declares no view is not a drawing change', got.ok])

  got = run({
    diffText: diff(
      'apps/ios/Packages/StoryArcKit/Tests/LibraryFeatureTests/ShelfTests.swift',
      5,
      ['        Text("count")'],
    ),
  })
  cases.push(['a test source is never a drawing change', got.ok])

  got = run({ diffText: diff('scripts/preview-proof-check.mjs', 5, ['const x = 1']) })
  cases.push(['a change outside the two app trees is not judged', got.ok && got.drawing.length === 0])

  got = run({ diffText: diff('apps/ios/App/Missing.swift', 5, ['        Text("count")']) })
  cases.push(['a file the branch no longer holds is skipped', got.ok])

  cases.push(['a directory is not a frame', analyse({
    diffText: swiftBody,
    contentOf: (path) => contents[path] ?? null,
    framePaths: [`${FRAMES}shelf-2026-09-12/`],
    messages: [''],
  }).ok === false])

  cases.push(untrackedFrameCase())

  const ranges = previewRanges(composable, 'kotlin')
  cases.push(['a Compose preview block spans its annotations and its body', ranges.length === 1
    && ranges[0][0] === 8 && ranges[0][1] === 12])

  let failed = 0
  for (const [name, ok] of cases) {
    console.log(`  ${ok ? 'pass' : 'FAIL'}  ${name}`)
    if (!ok) failed += 1
  }
  console.log(`preview-proof self-test: ${cases.length - failed}/${cases.length} passed`)
  return failed ? 1 : 0
}

// The rule is exported so it can be read from outside, and nothing runs on an import.
if (process.argv[1] !== fileURLToPath(import.meta.url)) {
  // imported
} else if (process.argv.includes('--self-test')) {
  process.exit(selfTest())
} else {
  try {
    process.exit(check())
  } catch (error) {
    console.log(
      `preview-proof: git could not answer here (${error.message.split('\n')[0]}), so there is no verdict.`,
    )
    process.exit(0)
  }
}
