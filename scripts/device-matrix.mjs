#!/usr/bin/env node
/**
 * The project's device matrix, written down once.
 *
 * `AGENTS.md` section 6 and `native-experience`'s "Both appearances" scenario both ask for a
 * changed screen in light and dark, at the default text size. Until now that
 * sentence was the only copy of the matrix, so every sweep was taken from memory and what a
 * change actually photographed varied with whoever took it. `capture-android.mjs` and
 * `capture-ios.mjs` loop over this table in `--matrix` mode, and `capture-compare.mjs` reads
 * the ignored band from it, so a condition is added here and nowhere else.
 *
 * Usage:
 *   node scripts/device-matrix.mjs                  print the table
 *   node scripts/device-matrix.mjs --devices fold   boot each named device and write a frame per state
 *   node scripts/device-matrix.mjs --self-test      check the device table against itself
 */
import assert from 'node:assert/strict'
import { execFileSync, spawn } from 'node:child_process'
import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { adbRunner, resolveAdb } from './adb.mjs'

/**
 * The share of each frame, from the top down, that a comparison ignores.
 *
 * **This is the status bar, and it is ignored because the clock moves.** Measured on
 * 2026-09-12 over the 1004 PNGs under `docs/designs/screenshots/`: of 108 pairs of frames
 * filed under the same name, three differ in nothing but rows 79 to 116, columns 157 to 287,
 * of a 1206x2622 iOS frame. That rectangle is the simulator's clock. It accounts for 0.067%
 * to 0.080% of those frames, and it is the entire difference between two photographs of one
 * screen taken on different days.
 *
 * Row 116 is 4.43% of 2622. Six percent is 158 rows on that frame, which clears the lowest
 * measured varying row by 42 rows, and 144 rows on the 1080x2400 Android frame.
 *
 * **What it costs, said plainly.** Six percent of an Android frame is about 52 dp, and an
 * Android status bar is 24 dp, so the band also swallows the top half of the app bar: a
 * regression in the height of the app bar's top padding would not be seen. The corpus holds
 * no Android pair differing only in its status bar, so the Android band is the iOS figure
 * applied across rather than a measurement of its own. `capture-compare.mjs` prints the
 * topmost differing row of every frame it reports, which is the number that would say so.
 */
export const IGNORE_TOP_PERCENT = 6

/**
 * The largest differing fraction a comparison forgives, as a percentage of compared pixels.
 *
 * Measured the same day and over the same 108 pairs, with the band above removed: four pairs
 * are pixel-identical, and the smallest real change is 731 pixels of 2,436,480 — 0.030%.
 * Nothing lies between. So an unchanged screen produces exactly zero differing pixels, and
 * the smallest change anybody has filed produces 0.030%.
 *
 * 0.01% sits a third of the way to that smallest real change and is not zero, so a handful
 * of stray pixels does not fail a sweep: 297 pixels on a 1206x2622 iOS frame, 243 on a
 * 1080x2400 Android one. A threshold of zero would be unusable the first time a device
 * rendered one edge differently; a threshold of 0.1% would have forgiven a change this
 * project actually made.
 */
export const THRESHOLD_PERCENT = 0.01

/**
 * Every condition a sweep photographs, per platform.
 *
 * `suffix` is appended to a frame's name, so a light run and a dark run of one walk cannot
 * overwrite each other. The default condition carries no suffix, which is the convention
 * `capture-ios.mjs` already writes and the committed Android frames already use.
 */
export const MATRIX = {
  ios: {
    /** Named to `capture-ios.mjs --device`. A udid works too. */
    device: 'StoryArc-iPhone17Pro',
    /** Measured 2026-09-12: 435 of the 1004 committed frames are this size, more than any other. */
    frame: '1206x2622',
    /**
     * **The text size axis is missing here on purpose.** Frames are taken at the default text
     * size only. The largest text size is a test and review gate (`design.md` section 10), not
     * a frame. The app stores its settings as one JSON blob under a single key, so there is no
     * launch argument for the theme and the simulator's appearance is the only lever, which is
     * why `--appearance` exists.
     */
    conditions: [
      { appearance: 'light', textSize: 'default', suffix: '' },
      { appearance: 'dark', textSize: 'default', suffix: '-dark' },
    ],
  },
  android: {
    /**
     * Whatever is attached. `capture-android.mjs` passes no `-s` and lets `adb` read
     * `ANDROID_SERIAL`, so naming the device is the caller's business.
     */
    device: process.env.ANDROID_SERIAL ?? 'the attached device',
    /** Measured 2026-09-12: 393 of the 1004 committed frames are this size, more than any other. */
    frame: '1080x2400',
    /**
     * Frames are taken at font scale 1.0 only. The largest text size is a test and review
     * gate, not a frame. `capture-android.mjs --font-scale` stays for a developer who asks.
     */
    conditions: [
      { appearance: 'light', fontScale: '1.0', suffix: '' },
      { appearance: 'dark', fontScale: '1.0', suffix: '-dark' },
    ],
  },
}

/**
 * Devices a sweep boots by name, with `--devices <name>`.
 *
 * `fold` is the Pixel Fold (`native-experience`, *Foldable devices*, D7): the emulator profile
 * `pixel_fold`, on the API level CI uses. Each state is the emulator console's `posture <id>`
 * (`adb emu posture` prints the ids: 1 closed, 2 half-opened, 3 opened) and the display it shows.
 * The sizes are the device definition's own, at 420 dpi: the outer display is 1080 x 2092 px,
 * which is 411 x 797 dp, and the open one is 2208 x 1840 px, which is the 841 x 701 dp that
 * Android's large screen guidance names as the foldable test size.
 */
export const DEVICES = {
  fold: {
    avd: 'storyarc-fold',
    profile: 'pixel_fold',
    image: 'system-images;android-36;google_apis;arm64-v8a',
    serial: 'emulator-5558',
    dpi: 420,
    states: [
      { name: 'closed', posture: 1, px: [1080, 2092], dp: [411, 797] },
      { name: 'open', posture: 3, px: [2208, 1840], dp: [841, 701] },
    ],
  },
}

/** A route or a walk name as a file name: lower case, one hyphen between words. */
export const slug = (name) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')

/** One condition as a sentence, for a log line. */
export const describe = (condition) =>
  [condition.appearance, condition.fontScale ? `font scale ${condition.fontScale}` : null, condition.textSize]
    .filter(Boolean)
    .join(', ')

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47])

/** The width and height a PNG's header states. */
export const pngSize = (png) => [png.readUInt32BE(16), png.readUInt32BE(20)]

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const wait = (millis) => new Promise((done) => setTimeout(done, millis))

/** Polls [test] until it is true. A poll, not a sleep: boot and a posture change have no event adb can wait on. */
async function until(what, test, millis) {
  const deadline = Date.now() + millis
  while (!(await test())) {
    if (Date.now() > deadline) throw new Error(`${what} did not happen within ${millis / 1000} s`)
    await wait(1000)
  }
}

/** Boots [device] (one emulator at a time), writes a frame per state to `.build/matrix/`, and stops it again. */
async function sweep(name) {
  const device = DEVICES[name]
  if (!device) throw new Error(`no device "${name}". Known: ${Object.keys(DEVICES).join(', ')}`)
  const adbPath = resolveAdb()
  const sdk = dirname(dirname(adbPath))
  const run = adbRunner(adbPath, { onDeviceError: 'empty' })
  const on = (...args) => run('-s', device.serial, ...args).trim()
  const running = run('devices').split('\n').map((line) => line.split('\t')[0]).filter((serial) => serial.startsWith('emulator-'))
  const others = running.filter((serial) => serial !== device.serial)
  if (others.length > 0) throw new Error(`another emulator runs (${others.join(', ')}). This Mac runs one emulator at a time: stop it first.`)

  let child = null
  if (!running.includes(device.serial)) {
    if (!existsSync(join(homedir(), `.android/avd/${device.avd}.avd`))) {
      const avdmanager = spawn(join(sdk, 'cmdline-tools/latest/bin/avdmanager'),
        ['create', 'avd', '-n', device.avd, '-k', device.image, '-d', device.profile, '--force'], { stdio: ['pipe', 'inherit', 'inherit'] })
      avdmanager.stdin.end('no\n')
      await new Promise((done, fail) => avdmanager.on('exit', (code) => (code === 0 ? done() : fail(new Error(`avdmanager exited ${code}`)))))
    }
    child = spawn(join(sdk, 'emulator/emulator'), [
      '-avd', device.avd, '-port', device.serial.split('-')[1], '-memory', '2048', '-no-window', '-no-audio',
      '-no-boot-anim', '-no-snapshot-save',
    ], { detached: true, stdio: 'ignore' })
    child.unref()
    await until(`${device.avd} boot`, () => on('shell', 'getprop', 'sys.boot_completed') === '1', 300_000)
  }
  try {
    const out = join(ROOT, '.build/matrix')
    mkdirSync(out, { recursive: true })
    // A fold or an unfold can put the screen to sleep, and a sleeping display draws black.
    on('shell', 'svc', 'power', 'stayon', 'true')
    for (const state of device.states) {
      on('emu', 'posture', String(state.posture))
      on('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
      await until(`${name} ${state.name} awake`, () => on('shell', 'dumpsys', 'power').includes('mWakefulness=Awake'), 30_000)
      on('shell', 'wm', 'dismiss-keyguard')
      const size = `${state.px[0]}x${state.px[1]}`
      // The fold has two displays, and `screencap` with no `-d` takes the first, lit or not. The
      // frame is the display drawn at this state's size, once it is; it may come back turned.
      const displays = on('shell', 'dumpsys', 'SurfaceFlinger', '--display-id').match(/^Display \d+/gm) ?? []
      let png = null
      await until(`${name} ${state.name} at ${size}`, () => {
        png = displays.map((line) => {
          const shot = execFileSync(adbPath, ['-s', device.serial, 'exec-out', 'screencap', '-p', '-d', line.split(' ')[1]], { maxBuffer: 1 << 28 })
          return shot.subarray(shot.indexOf(PNG_SIGNATURE))
        }).find((frame) => [size, state.px.toReversed().join('x')].includes(pngSize(frame).join('x')))
        return png != null
      }, 30_000)
      const [width, height] = pngSize(png)
      const file = join(out, `${name}-${state.name}.png`)
      writeFileSync(file, png)
      console.log(`${name} ${state.name}: ${width}x${height} px (${state.dp.join(' x ')} dp) -> ${file}`)
    }
  } finally {
    if (child) {
      on('emu', 'kill')
      await until(`${device.avd} exit`, () => { try { process.kill(child.pid, 0); return false } catch { return true } }, 60_000)
    }
  }
}

function selfTest() {
  for (const [name, device] of Object.entries(DEVICES)) {
    for (const state of device.states) {
      const dp = state.px.map((px) => Math.round((px * 160) / device.dpi))
      assert.deepEqual(dp, state.dp, `${name} ${state.name}: ${state.px.join('x')} px at ${device.dpi} dpi is ${dp.join('x')} dp`)
    }
  }
  const header = Buffer.alloc(24)
  header.writeUInt32BE(2208, 16)
  header.writeUInt32BE(1840, 20)
  assert.deepEqual(pngSize(header), [2208, 1840])
  console.log('device-matrix self-test: passed')
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const argv = process.argv.slice(2)
  if (argv.includes('--self-test')) {
    selfTest()
    process.exit(0)
  }
  const devices = argv.includes('--devices') ? argv[argv.indexOf('--devices') + 1] : null
  if (devices) {
    for (const name of devices.split(',')) await sweep(name)
    process.exit(0)
  }
  for (const [platform, entry] of Object.entries(MATRIX)) {
    console.log(`${platform}: ${entry.device}, frames ${entry.frame}`)
    for (const condition of entry.conditions) {
      console.log(`  ${describe(condition)}  ->  <name>${condition.suffix}.png`)
    }
  }
  console.log(`\nA comparison ignores the top ${IGNORE_TOP_PERCENT}% of a frame`)
  console.log(`and fails above ${THRESHOLD_PERCENT}% of the remaining pixels.`)
}
