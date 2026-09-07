# Design

## The shape

The screen already has one idiom for a row that leaves the app: `Link` on iOS and `LinkRow`
on Android. Both wrap a label and open a URL. The byline becomes one of those, in place.

It keeps its position in the top block, beside the version and the free statement. The block
holds facts about this build, and the author is such a fact. Moving the byline down into the
block of ways out would put the handle below the licence, and a reader looks for a byline
first.

## Why the handle and not the name

A handle is an address. A reader who sees `@me-cedric` can find the person; a reader who sees
a legal name cannot. The name stays in the repository metadata and in every ADR, which is
where a name belongs.

## Why the separate row goes

The spec asks that About shows "a link to <https://github.com/me-cedric>". One link satisfies
that. Two rows to the same address is the defect this change came from, so keeping the second
row would leave the change half made.

## Refused: markdown inside the localized string

SwiftUI renders a markdown link inside a `Text` from a `LocalizedStringKey`, so
`By [@me-cedric](https://github.com/me-cedric)` would make only the handle tappable. That was
refused for three reasons. The URL would enter a translatable string, where a translator can
break it. Compose has no matching one-liner, so the two platforms would diverge in mechanism
for no gain. And the screen already has an idiom for this, which a reader of either codebase
already knows.

The whole row is tappable instead of the handle alone. On a settings list that is the
expected target size, and it is what every other link on this screen does.

## Refused: keeping both rows and only renaming the byline

That leaves two controls to one address, and the smaller of the two still does nothing.
