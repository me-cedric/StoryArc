#!/usr/bin/env node
/**
 * Takes the store screenshots of both apps: six frames, five device sizes, four languages.
 *
 * Three lanes run at the same time, each with its own agent-device session: the Android
 * emulator (Play's three buckets, one after the other, set by `wm size` and `wm density`),
 * the 6.9-inch iPhone simulator and the 13-inch iPad simulator. Each lane opens the app once
 * per language and walks the frames in one path (`walk()` in `store-walk.mjs`). A frame is
 * taken when a wait has seen its screen, never after a fixed sleep, except where the step
 * says why no wait can see the screen.
 *
 * Output goes to `.build/store/` in fastlane's layouts. Git ignores it. Never commit it.
 *
 * Usage:
 *   node scripts/store-capture.mjs                           every lane, every language
 *   node scripts/store-capture.mjs --buckets phone,ipad-13   two of the five sizes
 *   node scripts/store-capture.mjs --locales fr --frames 04  one frame in one language
 *   node scripts/store-capture.mjs --library corpus          the test corpus, not the showcase
 *   node scripts/store-capture.mjs --no-build                use the app builds already there
 *   node scripts/store-capture.mjs --keep-devices            leave booted what this run booted
 *   node scripts/store-capture.mjs --verify                  check the files against the stores
 *
 * Buckets: phone, tablet7, tablet10 (Play) and iphone-6.9, ipad-13 (App Store).
 */
import { execFile, execFileSync, spawn } from 'node:child_process'
import { constants, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { promisify } from 'node:util'

import { resolveAdb } from './adb.mjs'
import { LIBRARY as SHOWCASE_DIR } from './store-showcase.mjs'
import {
  ANDROID_BUCKETS, FRAMES, IOS_BUCKETS, LIBRARIES, LOCALES, OUT, ROOT,
  labels, pngFileSize, shotPath, verify, walk,
} from './store-walk.mjs'

const exec = promisify(execFile)
const argv = process.argv.slice(2)
const flag = (name) => (argv.includes(`--${name}`) ? argv[argv.indexOf(`--${name}`) + 1] : null)
const list = (name, all) => (flag(name) ? flag(name).split(',').map((v) => v.trim()).filter(Boolean) : all)

const buckets = list('buckets', [...Object.keys(ANDROID_BUCKETS), ...Object.keys(IOS_BUCKETS)])
const locales = list('locales', Object.keys(LOCALES))
const frames = list('frames', FRAMES.map((f) => f.id))
  .flatMap((w) => FRAMES.filter((f) => f.id === w || f.name.includes(w)).map((f) => f.id))
const libraryName = flag('library') ?? 'showcase'
const androidBuckets = buckets.filter((b) => b in ANDROID_BUCKETS)
const iosBuckets = buckets.filter((b) => b in IOS_BUCKETS)

const unknown = [
  ...buckets.filter((b) => !(b in ANDROID_BUCKETS) && !(b in IOS_BUCKETS)),
  ...locales.filter((l) => !(l in LOCALES)),
  ...(libraryName in LIBRARIES ? [] : [libraryName]),
]
if (unknown.length > 0 || frames.length === 0) {
  console.error(`Unknown: ${unknown.join(', ') || 'frames'}. Buckets: ${[...Object.keys(ANDROID_BUCKETS), ...Object.keys(IOS_BUCKETS)].join(', ')}. Locales: ${Object.keys(LOCALES).join(', ')}. Libraries: ${Object.keys(LIBRARIES).join(', ')}.`)
  process.exit(2)
}

if (argv.includes('--verify')) {
  const { counted, failures } = verify({ locales, frames, androidBuckets, iosBuckets })
  for (const failure of failures) console.error(`  ${failure}`)
  console.log(`store verify: ${counted} asset(s) checked, ${failures.length} problem(s).`)
  process.exit(failures.length === 0 ? 0 : 1)
}

// Every label in every language, before a device boots. A renamed key stops the run here.
const words = {}
for (const locale of locales) {
  words[`android/${locale}`] = labels('android', locale)
  words[`ios/${locale}`] = labels('ios', locale)
}

const library = LIBRARIES[libraryName]
const LIBRARY_DIR = libraryName === 'showcase' ? SHOWCASE_DIR : join(ROOT, '.build/store-corpus')
if (libraryName === 'corpus' && !existsSync(LIBRARY_DIR)) {
  await exec(process.execPath, [join(ROOT, 'scripts/corpus.mjs'), LIBRARY_DIR])
}
const present = library.files.filter((file) => existsSync(join(LIBRARY_DIR, file)))
if (present.length === 0) {
  console.error(`The ${libraryName} library at ${LIBRARY_DIR} is empty. Run \`pnpm store:showcase\` with the source mounted, or pass --library corpus.`)
  process.exit(1)
}
for (const file of library.files.filter((f) => !present.includes(f))) console.error(`  not in the library: ${file}`)

const started = Date.now()
const seconds = (from = started) => `${((Date.now() - from) / 1000).toFixed(1)}s`

// ---------------------------------------------------------------------------------------
// agent-device, at the version `pnpm device` pins.
// ---------------------------------------------------------------------------------------

const PINNED = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8')).scripts.device.match(/agent-device@[\d.]+/)[0]
const AGENT_DEVICE = (await exec('npx', ['-y', '--package', PINNED, '-c', 'command -v agent-device'], { cwd: ROOT })).stdout.trim()

/** One agent-device command. Returns its JSON `data`; throws its error message. */
async function ad(args) {
  let stdout = ''
  try {
    stdout = (await exec(AGENT_DEVICE, [...args, '--json'], { maxBuffer: 1 << 26 })).stdout
  } catch (error) {
    stdout = error.stdout ?? ''
    if (!stdout.trim().startsWith('{')) throw new Error(`agent-device ${args[0]}: ${(error.stderr || error.message).trim().split('\n')[0]}`)
  }
  const result = JSON.parse(stdout)
  if (!result.success) throw new Error(`agent-device ${args[0]}: ${result.error?.message ?? stdout.slice(0, 300)}`)
  return result.data
}

// ---------------------------------------------------------------------------------------
// The walk, driven: batches of steps, with a snapshot only where a step must find a node.
// ---------------------------------------------------------------------------------------

/** Node kinds a tap prefers over a bare text node with the same words. */
const CONTROLS = new Set(['button', 'group', 'cell', 'link', 'tab', 'menu-item'])
/** Bars that float over content: a tap whose centre falls in one presses the bar. */
const BARS = new Set(['tab-bar', 'navigation-bar'])

/**
 * The centre of the first node with these words that is on screen and not under a bar.
 *
 * A node that carries the same label as its parent comes back with no label and
 * `inheritsLabel`. An iOS scroll area takes the label of its first cell, so without the
 * parent's label the walk would press the middle of the shelf instead of that cell.
 */
function find(nodes, viewport, words, exact) {
  const inside = (r, p) => p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height
  const byIndex = new Map(nodes.map((n) => [n.index, n]))
  const labelOf = (node) => (node.label || !node.inheritsLabel ? node.label : labelOf(byIndex.get(node.parentIndex) ?? {}))
  const bars = nodes.filter((n) => BARS.has(n.kind) && n.rect).map((n) => n.rect)
  const centres = nodes
    .map((node) => ({ ...node, label: labelOf(node) }))
    .filter(({ label, rect }) => label && rect && (exact ? words.includes(label.trim()) : words.some((w) => label.includes(w))))
    .filter(({ rect }) => rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= viewport.width && rect.y + rect.height <= viewport.height)
    .map((node) => ({ node, x: Math.round(node.rect.x + node.rect.width / 2), y: Math.round(node.rect.y + node.rect.height / 2) }))
    .filter((c) => exact || !bars.some((bar) => inside(bar, c)))
  const best = centres.find((c) => CONTROLS.has(c.node.kind)) ?? centres[0]
  return best && { x: best.x, y: best.y }
}

/**
 * Where to press for a `tap` step. When the words are not on screen, it presses an
 * `opener`, or scrolls: to the top once, since the shelf keeps its place, then down.
 */
async function locate(session, step) {
  const want = [].concat(step.tap)
  for (let attempt = 0; attempt < 7; attempt += 1) {
    const { nodes, viewport } = await ad(['snapshot', '-i', '--session', session])
    const target = find(nodes, viewport, want, step.exact)
    if (target) return target
    const opener = (step.openers ?? []).map((words) => find(nodes, viewport, words, true)).find(Boolean)
    if (opener) await ad(['press', String(opener.x), String(opener.y), '--settle', '--session', session])
    else if (step.scroll) await ad(['scroll', ...(attempt === 0 ? ['top'] : ['down', '0.4']), '--session', session]).catch(() => {})
  }
  throw new Error(`nothing on screen is labelled "${want.join('" or "')}"`)
}

async function isVisible(session, target) {
  try {
    await ad(['is', 'visible', target, '--session', session])
    return true
  } catch {
    return false
  }
}

/**
 * One batch of steps. The iOS runner refuses every step while a slow accessibility capture
 * of an earlier step still runs, as on the iPad player once in a full run. The steps before
 * the refused one are done, so the batch goes on from there. No event says that the runner is
 * free again, so it tries every three seconds, for half a minute at most.
 */
async function runBatch(session, steps) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await ad(['batch', '--steps', JSON.stringify(steps), '--on-error', 'stop', '--session', session])
    } catch (error) {
      const at = Number(error.message.match(/failed at step (\d+)/)?.[1])
      if (attempt === 10 || !at || !error.message.includes('still finishing a previous command')) throw error
      steps = steps.slice(at - 1)
      await new Promise((done) => setTimeout(done, 3000))
    }
  }
}

/** Runs the steps of one walk. `lane` knows the screen size and where each frame goes. */
async function run(lane, locale, steps) {
  const [width, height] = lane.points
  const at = ([fx, fy]) => ({ kind: 'point', x: Math.round(width * fx), y: Math.round(height * fy) })
  const centre = at([0.5, 0.5])
  let batch = []
  let shots = []
  const flush = async () => {
    if (batch.length === 0) return
    await runBatch(lane.session, batch)
    for (const { id, file } of shots) {
      const size = pngFileSize(file).join('x')
      if (size !== lane.size.join('x')) throw new Error(`frame ${id} came out ${size}, not ${lane.size.join('x')}`)
      console.log(`  [${lane.name}] ${lane.label(locale)} ${id} at ${seconds()}`)
    }
    batch = []
    shots = []
  }
  const wait = (input) => ({ command: 'wait', input: { timeoutMs: 15000, ...input } })
  const tapped = async (step) => ({ command: 'press', input: { target: { kind: 'point', ...(await locate(lane.session, step)) }, ...(step.settle ? { settle: true } : {}) } })
  for (let index = 0; index < steps.length; index += 1) {
    const step = steps[index]
    const next = steps[index + 1] ?? {}
    const expect = next.wait ? { selector: next.wait } : next.waitText ? { text: next.waitText } : null
    if (step.tap && expect) {
      // A busy app can drop a tap. When the next screen does not come, the walk checks
      // once more, then taps again, because the old screen is still there.
      await flush()
      const pair = async () => ad(['batch', '--steps', JSON.stringify([await tapped(step), wait(expect)]), '--on-error', 'stop', '--session', lane.session])
      try {
        await pair()
      } catch {
        const arrived = await ad(['batch', '--steps', JSON.stringify([wait({ ...expect, timeoutMs: 2000 })]), '--session', lane.session]).then(() => true, () => false)
        if (!arrived) await pair()
      }
      index += 1
    } else if (step.tap) {
      await flush()
      batch.push(await tapped(step))
    } else if (step.reveal) {
      // A tap in the middle toggles the reader's chrome, and the chrome hides itself a few
      // seconds after it shows. Chrome that is up may be about to go, so the walk hides it
      // and shows it again: the next press then has the chrome's whole time on screen. A
      // loaded simulator can still lose that race, so the walk tries a second time.
      await flush()
      const pressed = next.press === step.reveal ? [{ command: 'press', input: { target: { kind: 'selector', selector: step.reveal } } }] : []
      const reveal = async () => ad(['batch', '--steps', JSON.stringify([
        ...(await isVisible(lane.session, step.reveal) ? [{ command: 'press', input: { target: centre } }, wait({ absent: step.reveal })] : []),
        { command: 'press', input: { target: centre } }, wait({ selector: step.reveal }), ...pressed,
      ]), '--on-error', 'stop', '--session', lane.session])
      await reveal().catch(reveal)
      if (pressed.length > 0) index += 1
    } else if (step.turnUntil) {
      // A dropped turn leaves the same page, so the walk looks for the words before each turn.
      // `find` matches part of a label: a page's text is one long label, or one per paragraph.
      await flush()
      const shows = (ms) => ad(['find', step.turnUntil, 'wait', String(ms), '--session', lane.session])
      const edge = at([0.93, 0.5])
      for (let turn = 0; turn < step.most && !(await shows(1500).then(() => true, () => false)); turn += 1) {
        await ad(['press', String(edge.x), String(edge.y), '--settle', '--session', lane.session])
      }
      await shows(15000)
    } else if (step.until) {
      await flush()
      for (let attempt = 0; attempt < 4 && !(await isVisible(lane.session, step.until)); attempt += 1) {
        await ad(['press', step.press, '--session', lane.session]).catch(() => {})
        await ad(['wait', step.until, '3000', '--session', lane.session]).catch(() => {})
      }
      batch.push(wait({ selector: step.until }))
    } else if (step.press) batch.push({ command: 'press', input: { target: { kind: 'selector', selector: step.press } } })
    else if (step.point) batch.push({ command: 'press', input: { target: at(step.point), ...(step.settle ? { settle: true } : {}) } })
    else if (step.wait) batch.push(wait({ selector: step.wait, ...(step.timeoutMs ? { timeoutMs: step.timeoutMs } : {}) }))
    else if (step.waitAbsent) batch.push(wait({ absent: step.waitAbsent, ...(step.timeoutMs ? { timeoutMs: step.timeoutMs } : {}) }))
    else if (step.waitText) batch.push(wait({ text: step.waitText }))
    else if (step.stable) batch.push(wait({ stable: true, quietMs: 500 }))
    else if (step.pause) batch.push({ command: 'wait', input: { durationMs: step.pause } })
    else if (step.swipe) {
      const [from, to] = step.swipe.map(at)
      batch.push({ command: 'swipe', input: { from, to, count: step.count ?? 1, pauseMs: 300 } })
    }
    else if (step.scroll) batch.push({ command: 'scroll', input: { direction: 'down', amount: step.scroll } })
    else if (step.relaunch) {
      await flush()
      await lane.beforeRelaunch?.()
      await open(lane, locale)
    }
    else if (step.shot) {
      const file = lane.shot(locale, step.shot)
      mkdirSync(dirname(file), { recursive: true })
      batch.push({ command: 'screenshot', input: { path: file, ...lane.screenshot } })
      shots.push({ id: step.shot, file })
    }
  }
  await flush()
}

const open = (lane, locale) => ad(['open', lane.app, ...lane.device, '--session', lane.session, '--relaunch', ...lane.launchArgs(locale)])

/** One device, one language: the whole walk. */
async function walkOnce(lane, locale) {
  const steps = walk({
    platform: lane.platform,
    bucket: lane.bucket,
    library,
    labels: words[`${lane.platform}/${locale}`],
    frames,
  })
  await lane.reset(locale)
  await open(lane, locale)
  await run(lane, locale, steps)
}

/** Runs every language of one lane, and keeps going past a language that fails. */
async function walkAll(lane, failures) {
  for (const locale of locales) {
    try {
      await walkOnce(lane, locale)
    } catch (error) {
      // What the device showed when the walk stopped, for whoever reads the failure.
      const evidence = join(ROOT, '.build/store-logs', `${lane.name}-${lane.label(locale).replace('/', '-')}.png`)
      mkdirSync(dirname(evidence), { recursive: true })
      await ad(['screenshot', evidence, '--session', lane.session]).catch(() => {})
      failures.push(`[${lane.name}] ${lane.label(locale)}: ${error.message} (screen: ${evidence.slice(ROOT.length + 1)})`)
      console.error(`  [${lane.name}] ${lane.label(locale)} FAILED: ${error.message}`)
    }
  }
}

// ---------------------------------------------------------------------------------------
// The builds, once per run, started before the devices boot.
// ---------------------------------------------------------------------------------------

const APK = join(ROOT, 'apps/android/app/build/outputs/apk/debug/app-debug.apk')
const IOS_APP = join(ROOT, '.build/ios-store/Build/Products/Debug-iphonesimulator/StoryArc.app')
const build = argv.includes('--no-build')
  ? { android: Promise.resolve(), ios: Promise.resolve() }
  : {
      android: androidBuckets.length === 0 ? Promise.resolve() : (async () => {
        await exec(process.execPath, [join(ROOT, 'scripts/gradle.mjs'), ':app:assembleDebug', '--quiet'], { cwd: ROOT, maxBuffer: 1 << 26 })
        // The Gradle daemon would hold gigabytes for the rest of the run.
        await exec(process.execPath, [join(ROOT, 'scripts/gradle.mjs'), '--stop'], { cwd: ROOT })
        console.log(`  built the Android app at ${seconds()}`)
      })(),
      ios: iosBuckets.length === 0 ? Promise.resolve() : (async () => {
        await exec('xcodegen', ['generate', '--quiet'], { cwd: join(ROOT, 'apps/ios') })
        await exec('xcodebuild', [
          'build', '-project', 'apps/ios/StoryArc.xcodeproj', '-scheme', 'StoryArc',
          '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', '.build/ios-store', '-quiet',
        ], { cwd: ROOT, maxBuffer: 1 << 26 })
        console.log(`  built the iOS app at ${seconds()}`)
      })(),
    }
// Both lanes of a platform await one build; a failed build fails those lanes, not the run.
build.android.catch(() => {})
build.ios.catch(() => {})

// ---------------------------------------------------------------------------------------
// Android: one emulator, three buckets.
// ---------------------------------------------------------------------------------------

/**
 * A dedicated AVD on a `google_apis` image, which `adb root` works on. The library goes into
 * the app's own folder, which the app scans without a picker and only root can write.
 */
const AVD = 'storyarc-store'
const SERIAL = 'emulator-5556'
const PKG = 'com.mecedric.storyarc.debug'
const PARKED = '/data/local/tmp/storyarc-store'

async function androidLane(failures) {
  const adbPath = resolveAdb()
  const adb = async (...args) => (await exec(adbPath, ['-s', SERIAL, ...args], { maxBuffer: 1 << 26 })).stdout.trim()
  const shell = (command) => adb('shell', command)
  const quote = (text) => `'${text.replaceAll("'", "'\\''")}'`
  let emulator = { booted: false }
  const lane = {
    name: 'android', platform: 'android', session: 'store-android', app: PKG,
    device: ['--platform', 'android', '--serial', SERIAL], screenshot: {},
    label: (locale) => `${lane.bucketName}/${locale}`,
    shot: (locale, id) => shotPath('android', lane.bucketName, locale, id),
    launchArgs: () => [],
    // Every walk starts from the same app state, so the four languages show the same shelf.
    // Clearing the app's data with `pm clear` would also delete the library folder.
    reset: async (locale) => {
      await shell(`am force-stop ${PKG}; cd /data/data/${PKG} && rm -rf databases files no_backup shared_prefs cache`)
      await shell(`cmd locale set-app-locales ${PKG} --locales ${locale}`)
    },
  }
  try {
    emulator = await bootEmulator(adbPath)
    await adb('root')
    await adb('wait-for-device')
    await shell('settings put global window_animation_scale 0; settings put global transition_animation_scale 0; settings put global animator_duration_scale 0')
    await build.android
    await adb('install', '-r', '-g', APK)
    await syncAndroidLibrary(shell, adb, quote)
    for (const name of androidBuckets) {
      const { size, density } = ANDROID_BUCKETS[name]
      await shell(`wm size ${size[0]}x${size[1]}; wm density ${density}`)
      Object.assign(lane, { bucketName: name, bucket: ANDROID_BUCKETS[name], size, points: size })
      await walkAll(lane, failures)
    }
  } catch (error) {
    failures.push(`[android] ${error.message}`)
  } finally {
    await shell(`am force-stop ${PKG}; wm size reset; wm density reset; am broadcast -a com.android.systemui.demo -e command exit`).catch(() => {})
    await ad(['close', '--session', lane.session]).catch(() => {})
    if (emulator.booted && !argv.includes('--keep-devices')) await killEmulator(adbPath, emulator.pid)
  }
}

/** Boots the store AVD, unless it is up. Refuses when any other emulator runs. */
async function bootEmulator(adbPath) {
  const running = (await exec(adbPath, ['devices'])).stdout.split('\n')
    .map((line) => line.split('\t')[0]).filter((serial) => serial.startsWith('emulator-'))
  const others = running.filter((serial) => serial !== SERIAL)
  if (others.length > 0) throw new Error(`another emulator runs (${others.join(', ')}). This Mac runs one emulator at a time: stop it first.`)
  if (running.includes(SERIAL)) return { booted: false }
  const sdk = dirname(dirname(adbPath))
  const avds = (await exec(join(sdk, 'emulator/emulator'), ['-list-avds'])).stdout.split('\n').map((l) => l.trim())
  if (!avds.includes(AVD)) await createAvd(sdk)
  const child = spawn(join(sdk, 'emulator/emulator'), [
    '-avd', AVD, '-port', SERIAL.split('-')[1], '-memory', '2048', '-no-window', '-no-audio',
    '-no-boot-anim', '-no-snapshot-save',
  ], { detached: true, stdio: 'ignore' })
  child.unref()
  const deadline = Date.now() + 240_000
  while (Date.now() < deadline) {
    const booted = await exec(adbPath, ['-s', SERIAL, 'shell', 'getprop', 'sys.boot_completed']).then((r) => r.stdout.trim(), () => '')
    if (booted === '1') {
      console.log(`  [android] ${AVD} booted at ${seconds()}`)
      return { booted: true, pid: child.pid }
    }
    // A poll, not a sleep: boot has no event adb can wait on.
    await new Promise((done) => setTimeout(done, 1000))
  }
  throw new Error(`${AVD} did not boot within four minutes`)
}

async function killEmulator(adbPath, pid) {
  await exec(adbPath, ['-s', SERIAL, 'emu', 'kill']).catch(() => {})
  const deadline = Date.now() + 60_000
  while (Date.now() < deadline) {
    try {
      process.kill(pid, 0)
    } catch {
      return
    }
    await new Promise((done) => setTimeout(done, 500))
  }
}

/** The AVD the old store script made: the largest bucket's panel, room for the library. */
async function createAvd(sdk) {
  execFileSync(join(sdk, 'cmdline-tools/latest/bin/avdmanager'), [
    'create', 'avd', '-n', AVD, '-k', 'system-images;android-35;google_apis;arm64-v8a', '-d', 'pixel_7', '--force',
  ], { input: 'no\n' })
  const config = join(homedir(), `.android/avd/${AVD}.avd/config.ini`)
  let text = readFileSync(config, 'utf8')
  for (const [key, value] of Object.entries({
    'hw.lcd.width': '1440', 'hw.lcd.height': '2560', 'hw.lcd.density': '560',
    'disk.dataPartition.size': '12G', 'hw.ramSize': '2048', showDeviceFrame: 'no',
  })) {
    const line = new RegExp(`^${key.replaceAll('.', '\\.')}=.*$`, 'm')
    text = line.test(text) ? text.replace(line, `${key}=${value}`) : `${text.trimEnd()}\n${key}=${value}\n`
  }
  writeFileSync(config, text)
}

/**
 * Makes the app's folder hold exactly the library. A file already there, or parked from an
 * earlier run, is not pushed again: the audiobook alone is 386 MB. Nothing is deleted; a
 * file the library does not name moves to the parking folder.
 */
async function syncAndroidLibrary(shell, adb, quote) {
  const folder = `/sdcard/Android/data/${PKG}/files`
  await shell(`mkdir -p ${folder} ${PARKED}`)
  const listing = async (dir) => new Map((await shell(`cd ${dir} && for f in *; do [ -e "$f" ] && echo "$(stat -c %s "$f")|$f"; done`))
    .split('\n').filter((line) => line.includes('|')).map((line) => [line.slice(line.indexOf('|') + 1), Number(line.slice(0, line.indexOf('|')))]))
  const here = await listing(folder)
  const parked = await listing(PARKED)
  const want = new Map(library.files.filter((f) => existsSync(join(LIBRARY_DIR, f))).map((f) => {
    const stat = statSync(join(LIBRARY_DIR, f))
    return [f, stat.isDirectory() ? null : stat.size]
  }))
  const same = (have, size) => have !== undefined && (size === null || have === size)
  for (const name of here.keys()) {
    if (!want.has(name)) await shell(`mv ${quote(`${folder}/${name}`)} ${quote(`${PARKED}/${parked.has(name) ? `${name}.${Date.now()}` : name}`)}`)
  }
  let pushed = 0
  for (const [name, size] of want) {
    if (same(here.get(name), size)) continue
    if (same(parked.get(name), size)) await shell(`mv ${quote(`${PARKED}/${name}`)} ${quote(`${folder}/`)}`)
    else {
      await adb('push', join(LIBRARY_DIR, name), `${folder}/`)
      pushed += 1
    }
  }
  console.log(`  [android] library: ${want.size} publication(s), ${pushed} pushed, at ${seconds()}`)
}

// ---------------------------------------------------------------------------------------
// iOS: one simulator per bucket.
// ---------------------------------------------------------------------------------------

const BUNDLE = 'com.mecedric.storyarc'

/** The simulator of this model on the newest runtime that has one. */
async function simulator(model) {
  const listed = JSON.parse((await exec('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { maxBuffer: 1 << 26 })).stdout)
  const version = (runtime) => (runtime.match(/(\d+)-(\d+)$/) ?? [0, 0, 0]).slice(1).map(Number)
  const newer = (a, b) => a[0] - b[0] || a[1] - b[1]
  let found = null
  for (const [runtime, devices] of Object.entries(listed.devices)) {
    for (const device of devices) {
      if (device.name.startsWith(model) && (!found || newer(version(runtime), version(found.runtime)) > 0)) found = { ...device, runtime }
    }
  }
  if (!found) throw new Error(`no simulator called "${model}"`)
  return found
}

async function iosLane(name, failures) {
  const bucket = IOS_BUCKETS[name]
  const simctl = (...args) => exec('xcrun', ['simctl', ...args], { maxBuffer: 1 << 26 })
  let device = { udid: null, state: 'Booted' }
  const booted = () => device.state !== 'Booted'
  const lane = {
    name, platform: 'ios', session: `store-${name.split('-')[0]}`, app: BUNDLE, bucket, bucketName: name,
    size: bucket.size, points: bucket.size.map((side) => side / bucket.scale),
    device: [], screenshot: { pixelDensity: bucket.scale },
    label: (locale) => locale,
    shot: (locale, id) => shotPath('ios', name, locale, id),
    launchArgs: (locale) => ['-AppleLanguages', `(${locale})`, '-AppleLocale', locale].flatMap((arg) => ['--launch-args', arg]),
    // Every walk starts from the same app state. The library database lives in the app
    // group's container; the preferences go through `defaults`, so cfprefsd forgets them too.
    reset: async () => {
      await simctl('terminate', device.udid, BUNDLE).catch(() => {})
      for (const dir of ['Library/Application Support', 'Library/Saved Application State']) rmSync(join(lane.container, dir), { recursive: true, force: true })
      for (const dir of ['Library/Application Support', 'Widget']) rmSync(join(lane.group, dir), { recursive: true, force: true })
      await simctl('spawn', device.udid, 'defaults', 'delete', join(lane.container, 'Library/Preferences', BUNDLE)).catch(() => {})
    },
    // The registry records when the libraries last answered, and after a new launch the iPad
    // library says so at its foot, beside the player of frame 05. Without the registry the app
    // starts it again as on a first launch, with the same library and no such line.
    beforeRelaunch: async () => {
      await simctl('terminate', device.udid, BUNDLE).catch(() => {})
      await simctl('spawn', device.udid, 'defaults', 'delete', join(lane.container, 'Library/Preferences', BUNDLE), 'app.storyarc.sources').catch(() => {})
    },
  }
  try {
    device = await simulator(bucket.device)
    lane.device = ['--platform', 'ios', '--udid', device.udid]
    if (booted()) {
      await simctl('boot', device.udid)
      await simctl('bootstatus', device.udid, '-b')
      console.log(`  [${name}] ${device.name} (${device.runtime.split('.').pop()}) booted at ${seconds()}`)
    }
    await build.ios
    await simctl('install', device.udid, IOS_APP)
    lane.container = (await simctl('get_app_container', device.udid, BUNDLE, 'data')).stdout.trim()
    lane.group = (await simctl('get_app_container', device.udid, BUNDLE, `group.${BUNDLE}`)).stdout.trim()
    syncIosLibrary(lane.container, name)
    // A full date, so the iPad's status bar shows 9 Jan and not the day of the run. simctl
    // takes an ISO date only with milliseconds, and it draws Sun 9 Jan for this Tuesday.
    await simctl('status_bar', device.udid, 'override', '--time', new Date(2024, 0, 9, 9, 41).toISOString(), '--batteryState', 'charged',
      '--batteryLevel', '100', '--wifiBars', '3', '--cellularMode', 'active', '--cellularBars', '4')
    await walkAll(lane, failures)
  } catch (error) {
    failures.push(`[${name}] ${error.message}`)
  } finally {
    if (device.udid) {
      await simctl('terminate', device.udid, BUNDLE).catch(() => {})
      await simctl('status_bar', device.udid, 'clear').catch(() => {})
      await ad(['close', '--session', lane.session]).catch(() => {})
      if (booted() && !argv.includes('--keep-devices')) await simctl('shutdown', device.udid).catch(() => {})
    }
  }
}

/**
 * Makes `Documents` hold exactly the library, in `Documents/<folder>`. A copy is an APFS
 * clone, so even the audiobook costs nothing. Anything else in `Documents` moves to
 * `StoreParked` beside it, where the app does not look.
 */
function syncIosLibrary(container, name) {
  const documents = join(container, 'Documents')
  const into = join(documents, library.folder)
  const parked = join(container, 'StoreParked')
  mkdirSync(into, { recursive: true })
  mkdirSync(parked, { recursive: true })
  const park = (path, file) => renameSync(path, join(parked, existsSync(join(parked, file)) ? `${file}.${Date.now()}` : file))
  for (const entry of readdirSync(documents)) if (entry !== library.folder) park(join(documents, entry), entry)
  for (const entry of readdirSync(into)) if (!library.files.includes(entry)) park(join(into, entry), entry)
  let copied = 0
  for (const file of present) {
    const from = join(LIBRARY_DIR, file)
    const to = join(into, file)
    if (existsSync(to) && statSync(to).size === statSync(from).size) continue
    if (statSync(from).isDirectory()) {
      mkdirSync(to, { recursive: true })
      for (const part of readdirSync(from)) copyFileSync(join(from, part), join(to, part), constants.COPYFILE_FICLONE)
    } else copyFileSync(from, to, constants.COPYFILE_FICLONE)
    copied += 1
  }
  console.log(`  [${name}] library: ${present.length} publication(s), ${copied} copied, at ${seconds()}`)
}

// ---------------------------------------------------------------------------------------
// The run.
// ---------------------------------------------------------------------------------------

console.log(`store capture: ${libraryName} library, ${buckets.join(', ')}; ${locales.join(', ')}; frames ${frames.join(', ')}`)
const failures = []
await Promise.all([
  ...(androidBuckets.length > 0 ? [androidLane(failures)] : []),
  ...iosBuckets.map((name) => iosLane(name, failures)),
])
for (const failure of failures) console.error(`  ${failure}`)
console.log(`store capture: ${failures.length} failure(s) in ${seconds()}. Files under ${OUT}.`)
process.exit(failures.length === 0 ? 0 : 1)
