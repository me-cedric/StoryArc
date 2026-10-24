// args.mjs — one strict flag parser for every compass script, wrapping
// node:util parseArgs. Fixes the ad-hoc parsing footguns: unknown flags now
// error instead of being silently ignored, `--flag=value` works, `-h` never
// lands in a positional, and a value flag can no longer swallow the next flag.
//
// Usage in a script:
//   const { values, positionals } = parseCliArgs({
//     name: 'sync',
//     summary: "Reconcile a host's managed agent-compass files.",
//     positionals: [{ name: 'host-dir', required: false }],
//     options: {
//       dry: { type: 'boolean', desc: 'Show what would change; write nothing.' },
//       target: { type: 'string', value: '<ver>', desc: 'Override the version.' },
//     },
//   })

import { parseArgs } from 'node:util'
import { resolve } from 'node:path'

// Pure core — returns a result object instead of exiting, so tests can drive it.
export const tryParse = ({ options = {}, positionals = [], argv = [] }) => {
  const spec = { help: { type: 'boolean', short: 'h' } }
  for (const [key, opt] of Object.entries(options)) {
    spec[key] = { type: opt.type || 'boolean' }
    if (opt.short) spec[key].short = opt.short
    if (opt.multiple) spec[key].multiple = true
    if (opt.default !== undefined) spec[key].default = opt.default
  }
  let parsed
  try {
    parsed = parseArgs({ args: argv, options: spec, allowPositionals: true, strict: true })
  } catch (err) {
    return { ok: false, error: err.message }
  }
  if (parsed.values.help) return { ok: true, help: true, values: parsed.values, positionals: parsed.positionals }
  if (parsed.positionals.length > positionals.length) {
    return { ok: false, error: `Unexpected argument: ${parsed.positionals[positionals.length]}` }
  }
  return { ok: true, help: false, values: parsed.values, positionals: parsed.positionals }
}

export const renderHelp = ({ name, summary = '', usage, options = {}, positionals = [], script }) => {
  const posUsage = positionals.map((p) => (p.required ? `<${p.name}>` : `[${p.name}]`)).join(' ')
  const line = usage || `agent-compass ${name}${posUsage ? ` ${posUsage}` : ''} [options]`
  const rows = [...Object.entries(options), ['help, -h', { desc: 'Show this help.' }]]
    .map(([key, opt]) => {
      const flag = key === 'help, -h' ? '--help, -h' : `--${key}${opt.value ? ` ${opt.value}` : ''}`
      return `  ${flag.padEnd(20)} ${opt.desc || ''}`
    })
  return `Usage: ${line}${script ? `\n       (direct: node scripts/${script})` : ''}

${summary}

Options:
${rows.join('\n')}
`
}

// IO wrapper — prints help / errors and exits; scripts call this one.
export const parseCliArgs = (config) => {
  const argv = config.argv ?? process.argv.slice(2)
  const result = tryParse({ ...config, argv })
  if (!result.ok) {
    console.error(`${result.error}\nRun with --help for usage.`)
    process.exit(1)
  }
  if (result.help) {
    console.log(renderHelp(config))
    process.exit(0)
  }
  return { values: result.values, positionals: result.positionals }
}

// Common idiom: first positional is the host/root dir, defaulting to cwd.
// Scripts that historically accepted `--root <dir>` pass it as `rootFlag`.
export const resolveRoot = (positionals, rootFlag) => resolve(rootFlag || positionals[0] || process.cwd())
