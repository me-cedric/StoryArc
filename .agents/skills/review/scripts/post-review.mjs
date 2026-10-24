#!/usr/bin/env node
// post-review.mjs — post a review on a GitHub pull request or a GitLab merge request: the summary, then the inline comments,
// then the verdict. No dependency. Run it from the repository, so gh and glab find the project from the git remote.
//   node post-review.mjs --pr <n> --review <review.json> [--forge github|gitlab] [--dry] [--json]
// review.json: { "summary": "<markdown>", "verdict": "approve|request_changes|comment", "comments": [{ "path", "line", "body" }] }
// --dry prints the recap and posts nothing. Show the recap to the user, and post only after a yes.
// A comment on a line outside the diff moves into the summary. A comment that an earlier thread already holds is skipped.
// The author of the change cannot approve it or request changes, so that verdict becomes a comment.
// AC_GH and AC_GLAB replace the gh and glab binaries (tests). Each call has a timeout and GIT_TERMINAL_PROMPT=0.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { parseArgs } from 'node:util'

const VERDICTS = ['approve', 'request_changes', 'comment']
const EVENT = { approve: 'APPROVE', request_changes: 'REQUEST_CHANGES', comment: 'COMMENT' }

const bin = (name) => {
  const b = process.env[`AC_${name.toUpperCase()}`] || name
  return /\.[cm]?js$/.test(b) ? [process.execPath, b] : [b]
}
const call = (name, args, input) => {
  const [cmd, ...pre] = bin(name)
  const r = spawnSync(cmd, [...pre, ...args], { input, encoding: 'utf8', timeout: 60_000, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } })
  if (r.error || r.status !== 0) throw new Error(`${name} ${args.slice(0, 3).join(' ')} failed: ${(r.stderr || r.error?.message || '').trim().split('\n')[0]}`)
  return r.stdout
}
const json = (text) => JSON.parse(text)
const lines = (text) => text.split('\n').filter((l) => l.trim()).map(json)

// The lines that a comment can anchor to: path → Map(new line → old line, or null for an added line).
// The +++ and --- lines count as headers only before the first hunk of a file.
export const diffLines = (diff, into = new Map(), path = null) => {
  let [oldN, newN, header] = [0, 0, path === null]
  for (const l of diff.split('\n')) {
    if (l.startsWith('diff --git')) { header = true; path = null; continue }
    if (header && l.startsWith('+++ ')) { path = l.slice(4).replace(/^b\//, ''); if (path === '/dev/null') path = null; continue }
    if (header && l.startsWith('--- ')) continue
    const h = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(l)
    if (h) { [oldN, newN, header] = [Number(h[1]), Number(h[2]), false]; continue }
    if (!path || header) continue
    if (!into.has(path)) into.set(path, new Map())
    if (l.startsWith('+')) into.get(path).set(newN++, null)
    else if (l.startsWith('-')) oldN++
    else if (l.startsWith(' ')) into.get(path).set(newN++, oldN++)
  }
  return into
}

// Split the comments: anchored ones, ones outside the diff (into the summary) and duplicates of an existing thread.
export const plan = (review, anchors, existing, { author, me }) => {
  const seen = new Set(existing.map((e) => `${e.path}\0${e.line}\0${String(e.body).trim()}`))
  const out = { inline: [], outside: [], duplicate: [] }
  for (const c of review.comments ?? []) {
    if (seen.has(`${c.path}\0${c.line}\0${String(c.body).trim()}`)) out.duplicate.push(c)
    else if (anchors.get(c.path)?.has(Number(c.line))) out.inline.push({ ...c, line: Number(c.line), old: anchors.get(c.path).get(Number(c.line)) })
    else out.outside.push(c)
  }
  const own = author && me && author === me
  out.verdict = own && review.verdict !== 'comment' ? 'comment' : review.verdict
  out.own = own
  out.summary = [review.summary.trim(), ...(out.outside.length ? ['', ...out.outside.map((c) => `- \`${c.path}:${c.line}\` — ${c.body}`)] : [])].join('\n')
  return out
}

const github = (n, review, dry) => {
  const pr = json(call('gh', ['pr', 'view', String(n), '--json', 'headRefOid,author']))
  const me = call('gh', ['api', 'user', '--jq', '.login']).trim()
  const anchors = diffLines(call('gh', ['pr', 'diff', String(n)]))
  const existing = lines(call('gh', ['api', `repos/{owner}/{repo}/pulls/${n}/comments`, '--paginate', '--jq', '.[] | {path, line, body}']))
  const p = plan(review, anchors, existing, { author: pr.author?.login, me })
  if (dry) return { ...p, head: pr.headRefOid }
  const body = { commit_id: pr.headRefOid, body: p.summary, event: EVENT[p.verdict], comments: p.inline.map((c) => ({ path: c.path, line: c.line, side: 'RIGHT', body: c.body })) }
  const posted = json(call('gh', ['api', `repos/{owner}/{repo}/pulls/${n}/reviews`, '--method', 'POST', '--input', '-'], JSON.stringify(body)))
  const count = Number(call('gh', ['api', `repos/{owner}/{repo}/pulls/${n}/reviews/${posted.id}/comments?per_page=100`, '--jq', 'length']).trim())
  return { ...p, head: pr.headRefOid, url: posted.html_url, degraded: count === p.inline.length ? [] : [`${p.inline.length - count} inline comments missing`] }
}

// GitLab pages: per_page=100, until a short page. The cap stops a runaway loop.
const pages = (path) => {
  const all = []
  for (let page = 1; page <= 50; page++) {
    const got = json(call('glab', ['api', `${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`]))
    all.push(...got)
    if (got.length < 100) break
  }
  return all
}

const gitlab = (n, review, dry) => {
  const mr = json(call('glab', ['api', `projects/:id/merge_requests/${n}`]))
  const me = json(call('glab', ['api', 'user'])).username
  const anchors = new Map()
  for (const d of pages(`projects/:id/merge_requests/${n}/diffs`)) if (!d.deleted_file) diffLines(d.diff ?? '', anchors, d.new_path)
  const existing = pages(`projects/:id/merge_requests/${n}/discussions`).flatMap((d) => d.notes ?? [])
    .filter((x) => x.position).map((x) => ({ path: x.position.new_path, line: x.position.new_line, body: x.body }))
  const p = plan(review, anchors, existing, { author: mr.author?.username, me })
  const refs = mr.diff_refs ?? {}
  if (dry) return { ...p, head: refs.head_sha }
  const post = (path, body) => json(call('glab', ['api', path, '--method', 'POST', '-H', 'Content-Type: application/json', '--input', '-'], JSON.stringify(body)))
  const note = post(`projects/:id/merge_requests/${n}/notes`, { body: p.summary })
  const degraded = []
  for (const c of p.inline) {
    const position = { position_type: 'text', base_sha: refs.base_sha, start_sha: refs.start_sha, head_sha: refs.head_sha, old_path: c.path, new_path: c.path, new_line: c.line, ...(c.old !== null && { old_line: c.old }) }
    // A refused post or a note without a position (a general thread) is a comment that GitLab could not anchor.
    // The run goes on, so the verdict still posts; a re-run skips the anchored ones.
    try {
      const d = post(`projects/:id/merge_requests/${n}/discussions`, { body: c.body, position })
      if (!d.notes?.[0]?.position) degraded.push(`${c.path}:${c.line}`)
    } catch { degraded.push(`${c.path}:${c.line}`) }
  }
  const notes = []
  if (p.verdict === 'approve') call('glab', ['mr', 'approve', String(n), '--sha', refs.head_sha])
  if (p.verdict === 'request_changes') {
    const approvers = json(call('glab', ['api', `projects/:id/merge_requests/${n}/approvals`])).approved_by ?? []
    if (approvers.some((a) => a.user?.username === me)) call('glab', ['mr', 'revoke', String(n)])
    notes.push(...requestChanges(n))
  }
  return { ...p, head: refs.head_sha, url: note.id ? `${mr.web_url}#note_${note.id}` : mr.web_url, degraded, notes }
}

// GitLab records "request changes" with the GraphQL mutation mergeRequestRequestChanges (Premium or Ultimate, 17.2 and later).
// Another instance refuses it: the summary still states the verdict, and the run says so.
const requestChanges = (n) => {
  const path = json(call('glab', ['api', 'projects/:id'])).path_with_namespace
  if (!/^[\w.-]+(\/[\w.-]+)+$/.test(path ?? '')) return ['GitLab did not record "request changes": the project path is not known']
  const query = `mutation { mergeRequestRequestChanges(input: { projectPath: "${path}", iid: "${n}" }) { errors } }`
  try {
    const r = json(call('glab', ['api', 'graphql', '-f', `query=${query}`]))
    const errors = [...(r.errors ?? []).map((e) => e.message), ...(r.data?.mergeRequestRequestChanges?.errors ?? [])]
    return errors.length ? [`GitLab did not record "request changes" (${errors[0]}); the summary states it`] : []
  } catch (err) { return [`GitLab did not record "request changes" (${err.message}); the summary states it`] }
}

// The forge of the origin remote: github.com is GitHub, a host with "gitlab" is GitLab. A self-hosted host is
// whichever CLI knows the repository: glab first, then gh (GitHub Enterprise).
export const forgeOf = () => {
  const url = spawnSync('git', ['remote', 'get-url', 'origin'], { encoding: 'utf8', timeout: 10_000 }).stdout ?? ''
  if (/github\.com[:/]/.test(url)) return 'github'
  if (/gitlab/i.test(url)) return 'gitlab'
  for (const [forge, args] of [['gitlab', ['repo', 'view', '-F', 'json']], ['github', ['repo', 'view', '--json', 'name']]]) {
    try { call(forge === 'gitlab' ? 'glab' : 'gh', args); return forge } catch {}
  }
  return null
}

const recap = (forge, n, r, dry) => [
  `${dry ? 'Recap (nothing posted)' : 'Posted'}: ${forge} #${n} at ${String(r.head ?? '').slice(0, 8)}, verdict ${r.verdict}${r.own ? ' (you are the author, so the verdict is a comment)' : ''}`,
  `Summary: ${r.summary.split('\n')[0].slice(0, 120)}${r.outside.length ? ` (+${r.outside.length} findings outside the diff)` : ''}`,
  `Inline: ${r.inline.length} comments${r.duplicate.length ? `, ${r.duplicate.length} duplicates skipped` : ''}`,
  ...r.inline.map((c) => `  ${c.path}:${c.line}  ${c.body.replace(/\s+/g, ' ').slice(0, 100)}`),
  ...(r.url ? [`URL: ${r.url}`] : []),
  ...(r.degraded?.length ? [`Not anchored: ${r.degraded.join(', ')}. Check them on the forge.`] : []),
  ...(r.notes ?? []).map((x) => `Note: ${x}`),
].join('\n')

const main = () => {
  const { values: v } = parseArgs({ options: { pr: { type: 'string' }, review: { type: 'string' }, forge: { type: 'string' }, dry: { type: 'boolean' }, json: { type: 'boolean' } } })
  if (!/^\d+$/.test(v.pr ?? '') || !v.review) throw new Error('usage: post-review.mjs --pr <n> --review <review.json> [--forge github|gitlab] [--dry] [--json]')
  const review = json(readFileSync(v.review, 'utf8'))
  if (typeof review.summary !== 'string' || !review.summary.trim()) throw new Error('review.json needs a "summary" text')
  if (!VERDICTS.includes(review.verdict)) throw new Error(`review.json needs a "verdict": ${VERDICTS.join(', ')}`)
  if (!Array.isArray(review.comments ?? [])) throw new Error('review.json "comments" must be a list')
  const bad = (review.comments ?? []).findIndex((c) => typeof c?.path !== 'string' || typeof c.body !== 'string' || !Number.isInteger(Number(c.line)) || Number(c.line) < 1)
  if (bad >= 0) throw new Error(`review.json comment ${bad + 1} needs a "path" text, a "line" number and a "body" text`)
  if (/co-authored-by|generated with/i.test(JSON.stringify(review))) throw new Error('the review holds an attribution line; remove it')
  const forge = v.forge ?? forgeOf()
  if (!['github', 'gitlab'].includes(forge)) throw new Error('the forge is not known from the origin remote; pass --forge github or --forge gitlab')
  const r = (forge === 'github' ? github : gitlab)(Number(v.pr), review, v.dry)
  console.log(v.json ? JSON.stringify({ ok: !r.degraded?.length, forge, ...r }, null, 2) : recap(forge, v.pr, r, v.dry))
  return r.degraded?.length ? 1 : 0
}

// Compare the file name only: Windows gives argv[1] with backslashes, and a symlinked skill dir gives another path.
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split(/[\\/]/).pop())) {
  try { process.exitCode = main() } catch (err) { console.error(`error: ${err.message}`); process.exitCode = 1 }
}
