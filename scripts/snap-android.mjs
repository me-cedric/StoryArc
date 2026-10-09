#!/usr/bin/env node
/**
 * Runs the Android screen catalogue: one snapshot test per screen and appearance, in the
 * modules that hold screens (`lighter-visual-check`).
 *
 *   node scripts/snap-android.mjs            verify every reference image; a changed picture fails
 *   node scripts/snap-android.mjs --record   record the reference images again
 *
 * A catalogue test class is named `Catalogue<number><Name>Test`, so `--tests` narrows each
 * module to those and the rest of its unit tests stay out of the run. `pnpm test:android`
 * runs the same tests, and verifies them, as part of the whole suite. A module that gains a
 * catalogue test is added to MODULES.
 */
import { spawnSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const MODULES = [':app', ':feature:library', ':feature:settings', ':feature:reader', ':feature:epubreader']

const record = process.argv.includes('--record')
const mode = record
    ? ['-Proborazzi.test.record=true', '-Proborazzi.test.verify=false']
    : ['-Proborazzi.test.verify=true']
const tasks = MODULES.flatMap((module) => [`${module}:testDebugUnitTest`, '--tests', '*.Catalogue*'])

const result = spawnSync('node', [join(ROOT, 'scripts/gradle.mjs'), ...mode, ...tasks], { stdio: 'inherit' })
process.exit(result.status ?? 1)
