---
id: compass-ui-change-needs-visual-proof
trigger: 'when you change a component, a stylesheet, a design token, or a page layout'
confidence: 0.9
domain: testing
source: local-repo-analysis
---

# A change the user can see arrives with a screenshot that proves it

## Action

Ship the screenshot with the change. A change that nobody looked at is not
finished.

A change is a user-interface change when it touches one of these:

- a component that renders markup
- a stylesheet, a CSS module, or a class list
- a design token: color, spacing, radius, type scale, motion
- a page layout, a route shell, or a navigation frame
- an asset the page shows: icon, image, or font

## The proof

Run Playwright. Capture one screenshot for each viewport in the project viewport
matrix. Compare each screenshot against the stored reference. Attach the changed
images, or the diff, to the handoff. The `visual-regression-playwright` skill
holds the commands and the folder layout.

## Why a class-name assertion is not proof

A test that asserts `toHaveClass('btn-primary')` still passes after somebody
deletes the `.btn-primary` rule from the stylesheet, so the button renders
unstyled and the suite stays green. A class name is a string. A pixel is the
product.

## The two exceptions

1. **Nothing renders the code yet.** The change sits behind a flag that no screen
   opens. Say so in the handoff. Capture the screenshots when the flag opens.
2. **A pure refactor.** Run the screenshot pass anyway. Byte-identical
   screenshots are the proof: they show that the refactor moved no pixel. Skipping
   the run proves nothing.

## When the project has no Playwright setup

Do not drop the proof in silence. Write one line in the handoff: `no visual
proof: project has no Playwright setup`. Then propose to add it, and name the
viewport matrix you recommend. Let the user decide.

See [[e2e-gate-budget]] for the run cost of a screenshot pass.
