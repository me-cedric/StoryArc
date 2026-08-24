---
id: negative-assertion-precondition
trigger: 'when a test asserts an absence — no dead selector survives, no forbidden class renders, no error reaches the log, no banned string ships'
confidence: 0.9
domain: testing
source: local-repo-analysis
---

# An absence assertion needs a presence precondition

A test that asserts "no X survives" also passes when the subject produced
nothing. A blank page carries no forbidden class. A process that never started
writes no forbidden log line. The suite reports green, and a reader takes the
green as proof.

This failure is silent and it scales. One broken lazy chunk turns a walk over
every route green while the application shows nothing.

## Assert the subject exists, then assert the absence

Put a floor assertion above the absence assertion, in the same test:

```ts
expect(
  await rendered(page),
  `${path} rendered nothing, so the class scan proves nothing`
).toBeGreaterThan(MIN_ELEMENTS);
expect(await survivors(page, path)).toEqual([]);
```

Set the floor from the emptiest legitimate state. A page with only a header
still carries a handful of elements, so a floor of five separates "empty state"
from "did not render".

## The floor must wait, not sample

A development server compiles each lazy chunk on its first request. A heavy
route — a diagram canvas, a chart — resolves after the shared readiness signal.
Sample the count straight away and the floor fails on whichever route is slow
that run.

Poll the floor with a generous timeout, then read the count once. Report the
count in the assertion message. A count reads better than a timeout stack.

## Make the absence value a list, not a boolean

Collect the survivors and assert the array is empty. The failure diff then names
each survivor and where the test found it. `true !== false` names nothing.

## A static search is not proof

Grep proves a literal is absent from source. It does not prove the value is
absent at runtime: a name reaches the output through string concatenation, a
class helper, a variable, or a library that renders into the same document.
Only the running subject answers the question.

## Keep the test after the deletion

The test outlives the change that motivated it. When somebody reintroduces a
removed name, the rule that supported it is gone, and this test fails first and
names the item.
