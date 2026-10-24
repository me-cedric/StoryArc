export const meta = {
  name: 'deliver',
  description: 'Deliver one goal: plan, split into file groups, workers, fresh-context review, at most 2 fix rounds',
  whenToUse: 'A change that touches more than one file and has a clear goal. Pass the goal as args.',
  phases: [{ title: 'Plan' }, { title: 'Build' }, { title: 'Review' }, { title: 'Fix' }],
}

const goal = typeof args === 'string' ? args : args?.goal
if (!goal) throw new Error('deliver: give the goal as args, for example "add a timeout to the sync command"')

const RULES = 'The style contract applies: ponytail full, i-have-adhd, caveman, and asd-ste100 for your report. Do not commit or push.'
const MAX_FIX_ROUNDS = 2
const strings = { type: 'array', items: { type: 'string' } }
const PLAN = {
  type: 'object',
  required: ['groups'],
  properties: {
    groups: {
      type: 'array',
      minItems: 1,
      maxItems: 2,
      items: { type: 'object', required: ['task', 'files', 'checks'], properties: { task: { type: 'string' }, files: strings, checks: strings } },
    },
  },
}
const REPORT = {
  type: 'object',
  required: ['changed', 'checks', 'open'],
  properties: {
    changed: strings,
    checks: {
      type: 'array',
      items: { type: 'object', required: ['command', 'result'], properties: { command: { type: 'string' }, result: { enum: ['passed', 'failed', 'not run'] } } },
    },
    open: strings,
  },
}
const FINDINGS = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: { type: 'object', required: ['file', 'defect', 'fix'], properties: { file: { type: 'string' }, line: { type: 'integer' }, defect: { type: 'string' }, fix: { type: 'string' } } },
    },
  },
}

phase('Plan')
const plan = await agent(
  `${RULES}\nGoal: ${goal}\nRead the code that the goal touches. Split the work into one or two groups. Two groups must not share a file. ` +
  'For each group, give the task, the files to edit, and the check commands.',
  { label: 'plan', phase: 'Plan', schema: PLAN },
)
if (!plan) return { status: 'partial', blocker: 'the plan step did not return a plan' }

const checks = [...new Set(plan.groups.flatMap((g) => g.checks))]
const files = plan.groups.flatMap((g) => g.files)
const work = (g, i) => agent(
  `${RULES}\nGoal: ${goal}\nTask: ${g.task}\nEdit only these files: ${g.files.join(', ')}\nThen run: ${g.checks.join('; ')}`,
  { label: `worker ${i + 1}`, phase: 'Build', agentType: 'worker', model: 'sonnet', schema: REPORT },
)

phase('Build')
let reports = []
if (new Set(files).size === files.length) reports = await parallel(plan.groups.map((g, i) => () => work(g, i)))
else for (const [i, g] of plan.groups.entries()) reports.push(await work(g, i))

const review = (n) => agent(
  `${RULES}\nGoal: ${goal}\nReview the change in these files for correctness only: ${files.join(', ')}\n` +
  'Run `git status --short`, then `git diff HEAD --` on these files, and read each untracked file that is in this list. ' +
  'Report bugs, a behavior that does not match the goal, and missing tests. Do not edit files.',
  { label: `review ${n}`, phase: 'Review', agentType: 'reviewer', model: 'sonnet', schema: FINDINGS },
)
// A failed or skipped check is a finding too, so a clean review alone does not end the work.
const failedChecks = (rs) => rs.flatMap((r) => (r?.checks.length ? r.checks : [{ command: 'a worker check', result: 'not run' }])
  .filter((c) => c.result !== 'passed')
  .map((c) => ({ file: '(check)', defect: `${c.command}: ${c.result}`, fix: 'make the check pass' })))

let latest = reports
let found = await review(1)
let issues = [...(found?.findings ?? []), ...failedChecks(latest)]
let rounds = 0
while (found && issues.length && rounds < MAX_FIX_ROUNDS) {
  rounds++
  const fix = await agent(
    `${RULES}\nGoal: ${goal}\nFix these findings. Edit only these files: ${files.join(', ')}. Change only what each fix needs. ` +
    `Then run: ${checks.join('; ')}\n${JSON.stringify(issues, null, 2)}`,
    { label: `fix ${rounds}`, phase: 'Fix', agentType: 'worker', model: 'sonnet', schema: REPORT },
  )
  latest = [fix]
  found = await review(rounds + 1)
  issues = [...(found?.findings ?? []), ...failedChecks(latest)]
}

return {
  status: found && !issues.length ? 'review clean' : 'partial',
  note: 'Run the checks again yourself before you report done.',
  groups: plan.groups,
  reports: [...reports, ...(rounds ? latest : [])].filter(Boolean),
  fixRounds: rounds,
  openFindings: found ? issues : 'the review did not return',
}
