#!/usr/bin/env node

import { existsSync, readFileSync, realpathSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const START = 'compass: the style contract is on (ponytail full, i-have-adhd, caveman; asd-ste100 for durable text). ' +
  'One-line acknowledgement, no text between tool calls, one end summary with the changed files and each check with its result. ' +
  'The rules are in the compass block of AGENTS.md when the project has one, else in the compass-style skill.'

const TEMPLATE = /\.(example|sample|template)$/
const envFile = (p) => { const b = basename(p); return b.startsWith('.env') && !TEMPLATE.test(b) }
const words = (cmd) => cmd.split(/[\s'"`<>|;&()={},]+/).filter(Boolean)
const home = (p) => (p === '~' || p.startsWith('~/') ? join(homedir(), p.slice(1)) : p.replace(/^\$\{?HOME\}?(?=\/|$)/, homedir()))

const ENV_NAMES = ['.env', '.env.local', '.env.production', '.envrc']
const globHit = (glob) => {
  const re = new RegExp(`^${glob.split('/').pop().replace(/[.+^$()|\\]/g, '\\$&').replace(/\*+/g, '.*').replace(/\?/g, '.')
    .replace(/\{([^}]*)\}/g, (_, alt) => `(${alt.split(',').join('|')})`)}$`)
  return ENV_NAMES.find((n) => re.test(n))
}

// A key, a credential store or a keystore. A public key (.pub) is not a secret.
const SSH = /(^|[/\\])\.ssh([/\\]|$)/
const KEY_NAME = /^(id_(rsa|dsa|ecdsa|ed25519)(?!.*\.pub$).*|_?\.?netrc|google-services\.json|GoogleService-Info\.plist|[^.].*\.(pem|key|p12|pfx|keystore|jks))$/
const NPM_TOKEN = /^[^#;\n]*_(auth|authToken|password)\s*=\s*(?!\$\{)\S/m
const npmToken = (p) => { try { return NPM_TOKEN.test(readFileSync(home(p), 'utf8')) } catch { return false } }
const keyFile = (p) => SSH.test(p) || KEY_NAME.test(basename(p)) || (basename(p) === '.npmrc' && npmToken(p))
// A shell word counts only when it names a file that exists, so `e.key` in a script passes.
const keyWord = (w) => SSH.test(w) || (existsSync(home(w)) && keyFile(w))

const LOCKS = new Set(['package-lock.json', 'npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lock', 'bun.lockb', 'Podfile.lock',
  'Package.resolved', 'gradle.lockfile', 'Cargo.lock', 'composer.lock', 'Gemfile.lock', 'poetry.lock', 'uv.lock'])
const COMPASS_LOCK = /(^|[/\\])\.agents[/\\]compass\.lock\.json$/
const PATCH_FILE = /^\*\*\* (?:(?:Update|Add|Delete) File|Move to): (.+)$/gm
// The git internals and the secret stores of a project: an agent edits none of them.
const PROTECTED_DIR = /(^|[/\\])(\.git|secrets|credentials)[/\\]/
const lockEdit = (paths) => {
  const hit = paths.find((p) => COMPASS_LOCK.test(p) || LOCKS.has(basename(p)))
  if (!hit) return null
  const fix = COMPASS_LOCK.test(hit) ? 'Run ac sync to change it.' : 'Run the package manager to change a lock file.'
  return `compass: the edit of ${hit} is blocked. ${fix}`
}

// Codex has no deny rules, so the guard blocks the MCP tools that the Claude deny rules block.
const MCP_DENY = /worklog|delete/i
const mcpBlock = (name) => MCP_DENY.test(name.split('__').slice(2).join('__')) &&
  `compass: the tool ${name} is blocked because the contract forbids a worklog or a delete. Ask the user to do it.`

const shortFlag = (args, c) => args.some((a) => /^-[a-zA-Z]+$/.test(a) && a.includes(c))
const GIT_OPTS_WITH_VALUE = ['-C', '-c', '--git-dir', '--work-tree', '--namespace']
const gitArgs = (w) => {
  let i = w.findIndex((x) => basename(x) === 'git') + 1
  if (!i) return []
  while (w[i]?.startsWith('-')) i += GIT_OPTS_WITH_VALUE.includes(w[i]) ? 2 : 1
  return w.slice(i)
}
// --force-with-lease refuses to overwrite commits that the remote gained, so a rebased branch can use it after a yes.
// --force-if-includes only adds a check to it. A bare --force, -f or a + refspec stays blocked.
const LEASE = /^--force-(with-lease|if-includes)(=|$)/
const gitLease = (w) => { const [sub, ...args] = gitArgs(w); return sub === 'push' && args.some((a) => /^--force-with-lease(=|$)/.test(a)) }
const gitDanger = (w) => {
  const [sub, ...args] = gitArgs(w)
  if (sub === 'push') return args.some((a) => (a.startsWith('--force') && !LEASE.test(a)) || a.startsWith('+')) || shortFlag(args, 'f')
  if (sub === 'reset') return args.includes('--hard')
  if (sub === 'clean') return args.includes('--force') || shortFlag(args, 'f')
  return false
}
// A commit or push that skips the git hooks hides a failed check. `-n` is --no-verify for commit only.
// shortcut: a word "-n" inside an unquoted-looking commit message also matches; parse the -m value when that bites.
const gitSkip = (w) => {
  const [sub, ...args] = gitArgs(w)
  // Git takes a unique prefix of a long option, so --no-verif is --no-verify. A -c core.hooksPath= value skips the hooks too.
  const noVerify = args.some((a) => /^--no-veri/.test(a))
  const hooksPath = w.some((x, n) => w[n - 1] === '-c' && /^core\.hookspath=/i.test(x))
  return ['commit', 'push'].includes(sub) && (noVerify || hooksPath || (sub === 'commit' && shortFlag(args, 'n')))
}
// Every project rebases: a merge commit, or a pull that merges, is blocked. Ending a merge and a fast-forward stay allowed.
const MERGE_OK = ['--abort', '--continue', '--quit', '--ff-only']
const gitMerge = (w) => {
  const [sub, ...args] = gitArgs(w)
  if (sub === 'merge') return !args.some((a) => MERGE_OK.includes(a))
  if (sub === 'pull' && w.some((x, n) => w[n - 1] === '-c' && /^pull\.rebase=(true|merges|interactive)$/i.test(x))) return false
  if (sub === 'pull') return !args.some((a) => a === '-r' || a === '--ff-only' || (/^--rebase(=|$)/.test(a) && a !== '--rebase=false'))
  return false
}
const RISKY = new Set(['/', '~', '~/', '.', './', '..', '../', '*', '$HOME', '${HOME}'])
// `git rm` is undoable. A redirection ends the arguments. The command may be a path such as /bin/rm.
const rmDanger = (w, cwd, root) => {
  if (basename(w.find((x) => !/^\w+=/.test(x)) ?? '') === 'git') return false
  const i = w.findIndex((x) => basename(x) === 'rm')
  if (i < 0) return false
  const stop = w.findIndex((x, n) => n > i && /^\d*>/.test(x))
  const args = w.slice(i + 1, stop < 0 ? undefined : stop)
  if (!args.includes('--recursive') && !shortFlag(args, 'r') && !shortFlag(args, 'R')) return false
  return args.filter((a) => !a.startsWith('-')).some((a) => {
    if (RISKY.has(a) || /^(\.\/)?\*$/.test(a)) return true
    const rel = relative(root, resolve(cwd, home(a)))
    return rel === '' || rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel)
  })
}
const danger = (cmd, cwd) => {
  const root = process.env.CLAUDE_PROJECT_DIR || cwd
  let ask = null
  for (const s of cmd.split(/&&|\|\||[;|&\n()`]/).map((x) => x.trim())) {
    const w = s.split(/\s+/).map((x) => x.replace(/^['"]|['"]$/g, '')).filter(Boolean)
    if (gitDanger(w) || rmDanger(w, cwd, root)) return `compass: the command \`${s}\` is blocked because you cannot undo it. Ask the user to run it.`
    if (gitSkip(w)) return `compass: the command \`${s}\` is blocked because it skips the git hooks. Fix the hook failure, or ask the user to skip it.`
    if (gitMerge(w)) {
      return `compass: the command \`${s}\` is blocked because the project rebases instead of merging. Run \`git fetch origin && git rebase origin/<base>\`. ` +
        'A rebased branch needs `git push --force-with-lease`, which asks the user first.'
    }
    if (!ask && gitLease(w)) ask = { ask: `compass: \`${s}\` rewrites the remote branch. Approve it only for your own branch after a rebase.` }
  }
  return ask
}

const guard = (input) => {
  const name = typeof input.tool_name === 'string' ? input.tool_name : ''
  const t = input.tool_input || {}
  const cmd = Array.isArray(t.command) ? t.command.join(' ') : typeof t.command === 'string' ? t.command : ''
  if (name.startsWith('mcp__')) return mcpBlock(name)
  if (EDITS.has(name)) {
    const patch = [cmd, t.input, t.patch].filter((s) => typeof s === 'string').join('\n')
    const targets = [t.file_path, t.notebook_path, ...[...patch.matchAll(PATCH_FILE)].map((m) => m[1].trim())].filter((p) => typeof p === 'string')
    const kept = targets.find((p) => PROTECTED_DIR.test(p))
    if (kept) return `compass: the edit of ${kept} is blocked because .git/, secrets/ and credentials/ are not for agents. Ask the user.`
    return lockEdit(targets)
  }
  const paths = [t.file_path, t.path, t.notebook_path].filter((p) => typeof p === 'string')
  // Glob lists file names and reads no content, so only the Grep glob counts.
  const glob = name === 'Glob' ? undefined : t.glob
  const env = [...paths, ...words(cmd)].find(envFile) || (typeof glob === 'string' && globHit(glob))
  if (env) return `compass: the read of ${env} is blocked because .env files hold secrets. Read .env.example, or ask the user for the variable names.`
  const key = paths.find(keyFile) || words(cmd).find(keyWord)
  if (key) return `compass: the read of ${key} is blocked because the file holds a key, a token or a credential. Ask the user for the value that you need.`
  return danger(cmd, typeof input.cwd === 'string' ? input.cwd : process.cwd())
}

const EDITS = new Set(['Edit', 'MultiEdit', 'Write', 'NotebookEdit', 'apply_patch'])
// A call to a worker agent or to a workflow edits files too. ponytail: an edit through Bash (sed -i) is not seen.
const edits = (c) => c.type === 'tool_use' && (EDITS.has(c.name) || c.name === 'Workflow' ||
  (['Agent', 'Task'].includes(c.name) && c.input?.subagent_type === 'worker'))
const RESULT = /\b(pass(ed|es|ing)?|fail(ed|s|ing|ures?)?|succeeded|green|not run)\b/i

const textOf = (content) => (typeof content === 'string' ? content
  : Array.isArray(content) ? content.filter((c) => typeof c?.text === 'string').map((c) => c.text).join('\n') : '')

// The last turn of a Claude Code or Codex transcript: did it edit files, and what did the assistant say last?
const lastTurn = (path) => {
  let edited = false
  let text = ''
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    let e
    try { e = JSON.parse(line) } catch { continue }
    const p = e.payload || {}
    const content = e.message?.content
    const prompt = (e.type === 'user' && !e.isMeta && (typeof content === 'string' || content?.some?.((c) => c.type === 'text'))) ||
      (e.type === 'event_msg' && p.type === 'user_message')
    if (prompt) { edited = false; text = ''; continue }
    if (e.type === 'assistant' && Array.isArray(content)) {
      if (content.some(edits)) edited = true
      text = textOf(content) || text
    }
    if (e.type === 'response_item' && ['function_call', 'custom_tool_call'].includes(p.type) && EDITS.has(p.name)) edited = true
    if (e.type === 'response_item' && p.type === 'message' && p.role === 'assistant') text = textOf(p.content) || text
  }
  return { edited, text }
}

const gate = (input) => {
  if (input.stop_hook_active || typeof input.transcript_path !== 'string') return null
  const turn = lastTurn(input.transcript_path)
  const text = typeof input.last_assistant_message === 'string' ? input.last_assistant_message : turn.text
  if (!turn.edited || RESULT.test(text)) return null
  return 'compass completion gate: this turn changed files. End with one summary: the changed files, each check command, ' +
    'and its result (passed, failed, or not run with the reason). Do not say "done" when a check did not run.'
}

// The hint of a failed tool call from .agents/hints.json, written by ac reflect lesson (ADR 0007, phase 13).
// Claude and Copilot send a failure event with `error`. Codex sends PostToolUse for every call, so its output must show a failure.
// The hint is a plain substring match on the first 20,000 characters. The output holds the hint, never the error text.
const HINTS = '.agents/hints.json'
const CAPS = { hints: 50, match: 200, hint: 300, text: 20_000 }
const FAILED = /(^|\n)Exit code: [1-9]\d*|Process exited with code [1-9]\d*|verification failed|"exit_code":\s*[1-9]/
const hint = (input) => {
  const roots = [process.env.CLAUDE_PROJECT_DIR, join(dirname(fileURLToPath(import.meta.url)), '..', '..'), input.cwd, process.cwd()]
  const file = roots.filter((r) => typeof r === 'string' && r).map((r) => join(r, HINTS)).find((f) => existsSync(f))
  if (!file) return null
  const raw = input.error ?? input.tool_response ?? input.toolResult
  const text = (typeof raw === 'string' ? raw : JSON.stringify(raw ?? '')).slice(0, CAPS.text)
  if (input.error === undefined && !FAILED.test(text)) return null
  const tool = input.tool_name ?? input.toolName ?? ''
  const list = JSON.parse(readFileSync(file, 'utf8'))?.hints
  const hit = (Array.isArray(list) ? list.slice(0, CAPS.hints) : []).find((h) => typeof h?.match === 'string' && h.match &&
    h.match.length <= CAPS.match && typeof h.hint === 'string' && (!h.tool || h.tool === tool) && text.includes(h.match))
  if (!hit) return null
  const lesson = typeof hit.lesson === 'string' ? ` (${hit.lesson.slice(0, 120)})` : ''
  return `compass hint${lesson}: ${hit.hint.slice(0, CAPS.hint)}`
}

const read = () => { try { return JSON.parse(readFileSync(0, 'utf8') || '{}') } catch { return null } }

// The compass lock marks a project with its own copy. That copy sits beside the lock: .agents/hooks/ and .agents/compass.lock.json.
// A copy inside the project never steps back. A copy outside the project (the user plugin) steps back for an event only when
// the project hook runs it: the project lock owns the hook key of that event, or the project settings file lists a compass hook
// for it (the compass repository runs its own copy without a lock). A host that kept its own hooks still gets the .env guard.
// The hint runs on PostToolUseFailure in Claude Code and on PostToolUse in Codex.
const EVENTS = { start: 'SessionStart', guard: 'PreToolUse', gate: 'Stop', hint: process.env.CLAUDE_PROJECT_DIR ? 'PostToolUseFailure' : 'PostToolUse' }
const deferred = (mode) => {
  const real = (p) => { try { return realpathSync(p) } catch { return p } }
  const me = real(fileURLToPath(import.meta.url))
  const root = process.env.CLAUDE_PROJECT_DIR || process.cwd()
  const rel = relative(real(root), me)
  if (existsSync(join(dirname(me), '..', 'compass.lock.json')) || !(rel.startsWith('..') || isAbsolute(rel))) return false
  const json = (p) => { try { return JSON.parse(readFileSync(join(root, p), 'utf8')) } catch { return null } }
  const file = process.env.CLAUDE_PROJECT_DIR ? '.claude/settings.json' : '.codex/hooks.json'
  if (json('.agents/compass.lock.json')?.keys?.[file]?.[`hooks.${EVENTS[mode]}`]) return true
  const groups = json(file)?.hooks?.[EVENTS[mode]]
  const runs = new RegExp(`compass\\.mjs"? ${mode}( |$)`)
  return Array.isArray(groups) && groups.some((g) => g?.hooks?.some?.((h) => typeof h?.command === 'string' && runs.test(h.command)))
}

// Claude Code and Codex read plain stdout (start) and exit 2 with stderr (guard, gate). The Copilot cloud agent reads
// JSON on stdout only: additionalContext for a session start, permissionDecision for a tool call, decision for a stop.
// The generated .github/hooks/compass.json entries pass --copilot.
// The hint adds context only, so it fails open: an error prints nothing. Claude and Codex read hookSpecificOutput.
const mode = process.argv[2]
const copilot = process.argv.includes('--copilot')
const say = (text, json) => console.log(copilot ? JSON.stringify(json) : text)
if (!['start', 'guard', 'gate', 'hint'].includes(mode)) {
  console.error('usage: compass.mjs guard|gate|start|hint [--copilot]')
  process.exitCode = 1
} else if (!deferred(mode)) {
  if (mode === 'start') say(START, { additionalContext: START })
  else if (mode === 'hint') {
    let input = null
    let text = null
    try { input = read(); text = input && hint(input) } catch { text = null }
    const hookEventName = typeof input?.hook_event_name === 'string' ? input.hook_event_name : EVENTS.hint
    if (text) console.log(JSON.stringify(copilot ? { additionalContext: text } : { hookSpecificOutput: { hookEventName, additionalContext: text } }))
  } else {
    const input = read()
    let reason = null
    try { reason = input && (mode === 'guard' ? guard(input) : gate(input)) } catch { reason = null }
    if (reason?.ask) {
      // Claude Code and Copilot show the user a permission prompt. Codex has no ask decision (its input has a turn_id):
      // the call passes, the contract makes the agent ask in chat first, and the Codex network approval covers the push.
      if (copilot) console.log(JSON.stringify({ permissionDecision: 'ask', permissionDecisionReason: reason.ask }))
      else if (!input.turn_id) console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'ask', permissionDecisionReason: reason.ask } }))
    } else if (reason && mode === 'guard') {
      if (copilot) console.log(JSON.stringify({ permissionDecision: 'deny', permissionDecisionReason: reason }))
      console.error(reason)
      process.exitCode = 2
    } else if (reason && copilot) console.log(JSON.stringify({ decision: 'block', reason }))
    else if (reason) {
      console.error(reason)
      process.exitCode = 2
    }
  }
}
