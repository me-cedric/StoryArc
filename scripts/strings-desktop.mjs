#!/usr/bin/env node
/**
 * strings-desktop.mjs — one string source, two desktop formats.
 *
 *   node scripts/strings-desktop.mjs              write the .resw and .po files
 *   node scripts/strings-desktop.mjs --check      fail when a written file would change
 *   node scripts/strings-desktop.mjs --self-test  prove the check can fail, on a fixture
 *
 * `localization` promises four languages, and `desktop-experience` promises them in the
 * menus and dialogs of three desktops. The iOS string catalogues are the source: every
 * `Localizable.xcstrings` under the StoryArcKit and StoryArcEpub feature modules, the iOS app
 * target, and `packages/desktop-strings` for the keys only a desktop needs. macOS reads them as they are. Windows reads `.resw`, one per language, and
 * Linux reads gettext `.po`, one per language, so this writes both from the same catalogues
 * and `--check` fails `pnpm lint` the day either drifts from the source (task 2.8 of
 * `desktop-clients`).
 *
 * Three translations happen on the way, and each is named here because each is lossy:
 *
 *   KEYS        a `.resw` name is an identifier, so `catalogue.section.count %lld` becomes
 *               `catalogue_section_count__lld` and the original key is kept in the comment.
 *               gettext keeps the key verbatim as the msgid.
 *   PLACEHOLDERS  Swift's `%lld`, `%@` and `%1$@` become `{0}`, `{1}` in `.resw`, numbered in
 *               the order they appear or by their position, for `string.Format`; and `%d`,
 *               `%s`, `%1$s` in `.po`, which is what gettext's C format expects.
 *   PLURALS     a catalogue entry with `one` and `other` becomes two `.resw` entries, `_one`
 *               and `_other`, because Windows resources have no plural rule, and one gettext
 *               entry with `msgid_plural` and the language's `Plural-Forms` header.
 *
 * A key English defines that another language lacks fails the run: the build-time rule of
 * `localization` ("fails if any supported language is missing a key that English defines")
 * reaches the desktops through this script.
 */

import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const LANGUAGES = ['en', 'fr', 'de', 'es']
const SOURCE_LANGUAGE = 'en'

/** Where the catalogues are read from. The iOS app and its feature modules; nothing else. */
const CATALOGUE_ROOTS = [
  join(ROOT, 'apps', 'ios', 'App', 'Resources'),
  join(ROOT, 'apps', 'ios', 'Packages', 'StoryArcKit', 'Sources'),
  join(ROOT, 'apps', 'ios', 'Packages', 'StoryArcEpub', 'Sources'),
  // The strings only a desktop needs, in the same catalogue format. See its README.
  join(ROOT, 'packages', 'desktop-strings'),
]

/** Where the generated files go. Each desktop commits its copy, like the design tokens. */
const RESW_DIR = join(ROOT, 'apps', 'desktop-windows', 'src', 'StoryArc.Windows', 'Strings')
const PO_DIR = join(ROOT, 'apps', 'desktop-linux', 'po')

/** gettext plural rules for the four languages, from the Unicode CLDR cardinal rules. */
const PLURAL_FORMS = {
  en: 'nplurals=2; plural=(n != 1);',
  de: 'nplurals=2; plural=(n != 1);',
  es: 'nplurals=2; plural=(n != 1);',
  fr: 'nplurals=2; plural=(n > 1);',
}

// ── Reading the catalogues ────────────────────────────────────────────────────

const findCatalogues = (root) => {
  if (!existsSync(root)) return []
  const found = []
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === '.build' || entry.name.startsWith('.')) continue
      const path = join(dir, entry.name)
      if (entry.isDirectory()) walk(path)
      else if (entry.name === 'Localizable.xcstrings') found.push(path)
    }
  }
  walk(root)
  // By the `/` spelling, so Windows' `\` separators sort the catalogues in the same order.
  const slashed = (path) => path.replaceAll('\\', '/')
  return found.sort((a, b) => (slashed(a) < slashed(b) ? -1 : slashed(a) > slashed(b) ? 1 : 0))
}

/** The module a catalogue belongs to: the directory above `Resources`, or `App`. */
const moduleOf = (path) => {
  const parts = path.split(/[\\/]/)
  const resources = parts.lastIndexOf('Resources')
  const owner = resources > 0 ? parts[resources - 1] : parts[parts.length - 2]
  return owner === 'App' || owner === 'ios' ? 'App' : owner
}

/**
 * One merged table: key → { [language]: { value } | { one, other } }.
 *
 * On iOS each module looks a key up in its own bundle, so two modules may define the same
 * key with different words — the comic reader's `reader.menu.themes` says "Appearance" and
 * the EPUB reader's says "Reading themes", on purpose. A desktop has one table, so the
 * first catalogue keeps the bare key and every later disagreement is kept under
 * `key@Module`, and each is printed, so the desktop code chooses by name and nothing is
 * silently dropped. A disagreement whose source-language value is the same is a translation
 * drift between two iOS modules and is printed the same way.
 */
const readCatalogues = (paths) => {
  const table = new Map()
  const origins = new Map()
  const errors = []
  const collisions = []
  for (const path of paths) {
    const catalogue = JSON.parse(readFileSync(path, 'utf8'))
    for (const [rawKey, entry] of Object.entries(catalogue.strings ?? {})) {
      let key = rawKey
      const perLanguage = {}
      for (const [language, localization] of Object.entries(entry.localizations ?? {})) {
        if (!LANGUAGES.includes(language)) continue
        const plural = localization.variations?.plural
        if (plural) {
          perLanguage[language] = {
            one: plural.one?.stringUnit?.value ?? plural.other?.stringUnit?.value ?? '',
            other: plural.other?.stringUnit?.value ?? '',
          }
        } else if (localization.stringUnit) {
          perLanguage[language] = { value: localization.stringUnit.value ?? '' }
        }
      }
      if (Object.keys(perLanguage).length === 0) continue
      const previous = table.get(key)
      if (previous && JSON.stringify(previous) !== JSON.stringify(perLanguage)) {
        collisions.push(`"${rawKey}" differs between ${relative(ROOT, origins.get(key))} and ${relative(ROOT, path)}; the second is kept as "${rawKey}@${moduleOf(path)}"`)
        key = `${rawKey}@${moduleOf(path)}`
      }
      table.set(key, perLanguage)
      origins.set(key, path)
    }
  }
  return { table, errors, collisions }
}

/** Every key English defines must exist in every language, as a value or a plural pair. */
const missingTranslations = (table) => {
  const missing = []
  for (const [key, perLanguage] of table) {
    if (!perLanguage[SOURCE_LANGUAGE]) continue
    for (const language of LANGUAGES) {
      const entry = perLanguage[language]
      const empty = !entry || (entry.value === '' && entry.other === undefined) || entry.other === ''
      if (empty) missing.push(`${language}: "${key}"`)
    }
  }
  return missing
}

// ── Placeholders ──────────────────────────────────────────────────────────────

/** Swift format specifiers, positional or not, with their type letter. */
const SPECIFIER = /%(\d+\$)?(ll?d|u|@|s|d|f|\.\d+f)/g

/** `%lld` and friends → `{0}`, `{1}`: by position where given, else by order of appearance. */
const toDotNetPlaceholders = (text) => {
  let next = 0
  return text.replace(/%%/g, '\u0000').replace(SPECIFIER, (_, position) => {
    const index = position ? Number(position.slice(0, -1)) - 1 : next++
    return `{${index}}`
  }).replace(/\u0000/g, '%')
}

/** `%lld` → `%d`, `%@` → `%s`, positions kept, which is what gettext's C format reads. */
const toCPlaceholders = (text) =>
  text.replace(SPECIFIER, (_, position, type) => {
    const letter = type === '@' || type === 's' ? 's' : type.endsWith('f') ? 'f' : 'd'
    return `%${position ?? ''}${letter}`
  })

// ── Emitting ──────────────────────────────────────────────────────────────────

const reswName = (key) => key.replace(/[^A-Za-z0-9]/g, '_')
const xml = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

const emitResw = (table, language) => {
  const lines = [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<!-- Generated by scripts/strings-desktop.mjs from the iOS string catalogues — do not edit. -->',
    '<!-- Edit apps/ios/**/Localizable.xcstrings and run `pnpm strings:desktop`. -->',
    '<root>',
    '  <resheader name="resmimetype"><value>text/microsoft-resx</value></resheader>',
    '  <resheader name="version"><value>2.0</value></resheader>',
    '  <resheader name="reader"><value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>',
    '  <resheader name="writer"><value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>',
  ]
  for (const key of [...table.keys()].sort()) {
    const entry = table.get(key)[language] ?? table.get(key)[SOURCE_LANGUAGE]
    if (!entry) continue
    const name = reswName(key)
    if (entry.value !== undefined) {
      lines.push(`  <data name="${xml(name)}" xml:space="preserve">`)
      lines.push(`    <value>${xml(toDotNetPlaceholders(entry.value))}</value>`)
      lines.push(`    <comment>${xml(key)}</comment>`)
      lines.push('  </data>')
    } else {
      for (const form of ['one', 'other']) {
        lines.push(`  <data name="${xml(`${name}_${form}`)}" xml:space="preserve">`)
        lines.push(`    <value>${xml(toDotNetPlaceholders(entry[form]))}</value>`)
        lines.push(`    <comment>${xml(key)} (${form})</comment>`)
        lines.push('  </data>')
      }
    }
  }
  lines.push('</root>', '')
  return lines.join('\n')
}

const poQuote = (text) => `"${text.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`

const emitPo = (table, language) => {
  const lines = [
    '# Generated by scripts/strings-desktop.mjs from the iOS string catalogues — do not edit.',
    '# Edit apps/ios/**/Localizable.xcstrings and run `pnpm strings:desktop`.',
    'msgid ""',
    'msgstr ""',
    poQuote('Project-Id-Version: StoryArc\n'),
    poQuote(`Language: ${language}\n`),
    poQuote('MIME-Version: 1.0\n'),
    poQuote('Content-Type: text/plain; charset=UTF-8\n'),
    poQuote('Content-Transfer-Encoding: 8bit\n'),
    poQuote(`Plural-Forms: ${PLURAL_FORMS[language]}\n`),
    '',
  ]
  for (const key of [...table.keys()].sort()) {
    const entry = table.get(key)[language] ?? table.get(key)[SOURCE_LANGUAGE]
    if (!entry) continue
    const hasFormat = SPECIFIER.test(key) || SPECIFIER.test(entry.value ?? entry.other ?? '')
    SPECIFIER.lastIndex = 0
    if (hasFormat) lines.push('#, c-format')
    if (entry.value !== undefined) {
      lines.push(`msgid ${poQuote(toCPlaceholders(key))}`)
      lines.push(`msgstr ${poQuote(toCPlaceholders(entry.value))}`)
    } else {
      lines.push(`msgid ${poQuote(toCPlaceholders(key))}`)
      lines.push(`msgid_plural ${poQuote(toCPlaceholders(key))}`)
      lines.push(`msgstr[0] ${poQuote(toCPlaceholders(entry.one))}`)
      lines.push(`msgstr[1] ${poQuote(toCPlaceholders(entry.other))}`)
    }
    lines.push('')
  }
  return lines.join('\n')
}

/** Every file this script owns, as path → contents. */
const render = (table, reswDir = RESW_DIR, poDir = PO_DIR) => {
  const files = new Map()
  for (const language of LANGUAGES) {
    files.set(join(reswDir, language, 'Resources.resw'), emitResw(table, language))
    files.set(join(poDir, `${language}.po`), emitPo(table, language))
  }
  return files
}

// ── Modes ─────────────────────────────────────────────────────────────────────

const generate = ({ check, catalogues, reswDir, poDir }) => {
  const { table, errors, collisions } = readCatalogues(catalogues)
  for (const line of collisions) console.log(`strings-desktop: ${line}`)
  const missing = missingTranslations(table)
  if (errors.length || missing.length) {
    for (const line of errors) console.error(`strings-desktop: ${line}`)
    for (const line of missing) console.error(`strings-desktop: missing ${line}`)
    return 1
  }
  const files = render(table, reswDir, poDir)
  let drift = 0
  for (const [path, text] of files) {
    const current = existsSync(path) ? readFileSync(path, 'utf8') : null
    if (current === text) continue
    if (check) {
      console.error(`strings-desktop: ${relative(ROOT, path) || path} is out of date — run \`pnpm strings:desktop\``)
      drift += 1
    } else {
      mkdirSync(dirname(path), { recursive: true })
      writeFileSync(path, text)
      console.log(`  wrote ${relative(ROOT, path) || path}`)
    }
  }
  if (check && drift) return 1
  console.log(check
    ? `strings-desktop: ${files.size} files in sync, ${table.size} keys in ${LANGUAGES.length} languages.`
    : `strings-desktop: ${table.size} keys in ${LANGUAGES.length} languages.`)
  return 0
}

/** A catalogue of three shapes: a plain string, a positional format, and a plural. */
const fixtureCatalogue = (lacking = null) => {
  const unit = (value) => ({ stringUnit: { state: 'translated', value } })
  const localizations = (values) => Object.fromEntries(LANGUAGES
    .filter((language) => language !== lacking)
    .map((language) => [language, unit(values[language])]))
  return {
    sourceLanguage: 'en',
    version: '1.0',
    strings: {
      'appearance.dark': { localizations: localizations({ en: 'Dark', fr: 'Sombre', de: 'Dunkel', es: 'Oscuro' }) },
      'about.version %1$@ %2$@': { localizations: localizations({ en: 'Version %1$@ (%2$@)', fr: 'Version %1$@ (%2$@)', de: 'Version %1$@ (%2$@)', es: 'Versión %1$@ (%2$@)' }) },
      'catalogue.section.count %lld': {
        localizations: Object.fromEntries(LANGUAGES.map((language) => [language, {
          variations: { plural: { one: unit(`%lld ${language}-one`), other: unit(`%lld ${language}-other`) } },
        }])),
      },
    },
  }
}

const selfTest = () => {
  const scratch = mkdtempSync(join(tmpdir(), 'strings-desktop-'))
  const failures = []
  const check = (name, ok) => { if (!ok) failures.push(name); console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${name}`) }
  try {
    const catalogue = join(scratch, 'Localizable.xcstrings')
    writeFileSync(catalogue, JSON.stringify(fixtureCatalogue()))
    const reswDir = join(scratch, 'resw')
    const poDir = join(scratch, 'po')
    const quiet = { log: console.log, error: console.error }
    const silence = () => { console.log = () => {}; console.error = () => {} }
    const restore = () => { console.log = quiet.log; console.error = quiet.error }

    silence()
    const wrote = generate({ check: false, catalogues: [catalogue], reswDir, poDir })
    const inSync = generate({ check: true, catalogues: [catalogue], reswDir, poDir })
    restore()
    check('a fixture catalogue writes both formats', wrote === 0 && existsSync(join(reswDir, 'fr', 'Resources.resw')) && existsSync(join(poDir, 'de.po')))
    check('a second run finds nothing to change', inSync === 0)

    const resw = readFileSync(join(reswDir, 'en', 'Resources.resw'), 'utf8')
    check('a positional Swift format becomes numbered .NET placeholders', resw.includes('<value>Version {0} ({1})</value>'))
    check('a plural becomes _one and _other entries', resw.includes('name="catalogue_section_count__lld_one"') && resw.includes('name="catalogue_section_count__lld_other"'))
    check('the original key survives in the comment', resw.includes('<comment>about.version %1$@ %2$@</comment>'))

    const po = readFileSync(join(poDir, 'fr.po'), 'utf8')
    check('a plural becomes msgid_plural with two forms', po.includes('msgid_plural "catalogue.section.count %d"') && po.includes('msgstr[1] "%d fr-other"'))
    check('French carries its own plural rule', po.includes('Plural-Forms: nplurals=2; plural=(n > 1);'))
    check('%@ becomes %s for gettext', po.includes('msgstr "Version %1$s (%2$s)"'))

    const second = join(scratch, 'EpubReaderFeature', 'Resources', 'Localizable.xcstrings')
    mkdirSync(dirname(second), { recursive: true })
    const colliding = fixtureCatalogue()
    colliding.strings['appearance.dark'].localizations.en.stringUnit.value = 'Night'
    writeFileSync(second, JSON.stringify(colliding))
    silence()
    const merged = generate({ check: false, catalogues: [catalogue, second], reswDir, poDir })
    restore()
    const mergedPo = readFileSync(join(poDir, 'en.po'), 'utf8')
    check('a key two modules spell differently keeps both, the second under key@Module',
      merged === 0 && mergedPo.includes('msgid "appearance.dark"\nmsgstr "Dark"') && mergedPo.includes('msgid "appearance.dark@EpubReaderFeature"\nmsgstr "Night"'))

    writeFileSync(join(poDir, 'es.po'), '# edited by hand\n')
    silence()
    const drift = generate({ check: true, catalogues: [catalogue], reswDir, poDir })
    restore()
    check('a hand-edited output fails the check', drift === 1)

    writeFileSync(catalogue, JSON.stringify(fixtureCatalogue('de')))
    silence()
    const missing = generate({ check: true, catalogues: [catalogue], reswDir, poDir })
    restore()
    check('a key German lacks fails the run', missing === 1)
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
  if (failures.length) {
    console.error(`strings-desktop self-test: ${failures.length} check(s) failed`)
    return 1
  }
  console.log('strings-desktop self-test: 11 checks passed')
  return 0
}

const args = process.argv.slice(2)
if (args.includes('--self-test')) {
  process.exit(selfTest())
}
process.exit(generate({
  check: args.includes('--check'),
  catalogues: CATALOGUE_ROOTS.flatMap(findCatalogues),
}))
