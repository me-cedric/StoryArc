---
id: e2e-gate-budget
trigger: 'when an end-to-end suite grows past a few specs, a run starts to time out under parallel load, or somebody asks which tests the gate runs'
confidence: 0.9
domain: testing
source: local-repo-analysis
---

# Declare which end-to-end tests gate a change, and what they cost

An end-to-end suite has two populations. One set gates every change. One set runs
on demand — long walks, screenshot passes, anything that asserts little for many
minutes. Leave the split undeclared and the gate slows until somebody disables
it.

## Gate the slow subset behind a flag

Exclude the on-demand specs by default, and let one environment variable opt in:

```ts
testIgnore: process.env.SHOTS ? [] : ["**/screenshots.spec.ts"],
```

Give the opt-in its own command, so a contributor runs it without reading the
configuration.

## Set the two timeouts separately

A per-test budget and a per-assertion budget grow for different reasons:

- **Per test.** Count the navigations. One navigation against a development
  server costs seconds, and a spec that navigates three times spends that before
  it asserts anything.
- **Per assertion.** Parallel workers all load the module graph at once, so the
  first assertion of a run waits far longer than the default allows.

Raise the assertion timeout on its own. Raising only the test timeout leaves the
first assertion of the run failing under load.

## Record the measurement beside the number

Write the measured cost in a comment next to each budget, with the condition you
measured under:

```ts
// One navigation costs about 5 seconds against the dev server, measured with a
// warm module graph, so caching is not the variable. The slowest spec takes 18s.
timeout: 60_000,
```

A number with no measurement gets copied into the next project and fails there.
A number with a measurement tells the next reader whether the application grew or
the machine is slower.

## Keep the evidence for the run that fails

Retry once in continuous integration and never locally, so a local failure stays
visible. Capture a trace on the first retry only. A trace on every run costs time
on the passes, which are the runs nobody reads.
