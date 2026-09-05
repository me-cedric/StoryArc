## MODIFIED Requirements

### Requirement: Adaptive layout

The app SHALL adapt to every form factor its platform runs on, following the
platform's own reading-app conventions rather than scaling one layout — and each
platform SHALL express the destination set defined in
[`navigation-shell`](../navigation-shell/spec.md) with its own system
navigation, rather than with a translation of the other platform's.

> **The scenarios below keep every clause the main spec already holds.** A MODIFIED
> requirement replaces the whole block, so a clause this delta does not carry is a clause
> archiving deletes. `pnpm delta:drop` cannot see that: it compares scenarios by **name** and
> `SHALL` sentences in the requirement's prose, and says so in its own header — a bullet
> dropped inside a scenario that kept its name passes the check. Read against
> `specs/native-experience/spec.md` by hand, 2026-09-05, which is how the content-area clause
> in *Tablet and large screens* was found missing and restored below.
>
> **One clause is deliberately not carried word for word, and this is the record of it.**
> *Split View, Slide Over and multi-window* said "the **sidebar** collapses to an **overlay**".
> This requirement's own prose now forbids expressing one platform's navigation as a
> translation of the other's, and neither platform's compact form is an overlay sidebar: iOS
> reverts to its tab bar and Android to its bar. The normative half — *rather than being
> truncated* — is carried unchanged; only the name of the form it collapses to is generalised.

#### Scenario: Tablet and large screens
- **WHEN** the app runs on an iPad or an Android tablet
- **THEN** it uses a multi-column layout with persistent navigation alongside the content, not a stretched phone layout
- **AND** that navigation carries the same three destinations as the phone, plus sections of the library and the reader's shelves
- **AND** the content area shows the destination the reader is in and nothing else — the home surface's continue row, or the library's cover grid — which is the structure a reader on that platform already knows, now split across two destinations rather than stacked in one pane
- **AND** it never carries one entry per configured source, however many are configured

#### Scenario: The two platforms reach the same destinations differently
- **WHEN** the same destination set is presented on each platform
- **THEN** iOS presents it as a tab bar that adapts into a sidebar in a wide window, and Android presents it as a navigation bar that becomes a rail with a collapsed and an expanded state
- **AND** search is reached as [`navigation-shell`](../navigation-shell/spec.md) requires — a role of its own on iOS, a search field at the top of the browse surfaces on Android
- **AND** neither platform grows the other's control to make a screenshot pair match

#### Scenario: Split View, Slide Over and multi-window
- **WHEN** the app is resized on iPad or in Android multi-window
- **THEN** the layout reflows continuously and reading position is preserved through the resize
- **AND** navigation collapses to its compact form below the layout's regular width rather than being truncated

#### Scenario: Theme sheet on a large screen
- **WHEN** the theme sheet is opened on a tablet
- **THEN** it presents as a popover anchored to its control rather than a full-width sheet, and the reader stays visible beside it

#### Scenario: Foldables
- **WHEN** an Android foldable is unfolded, folded, or half-opened
- **THEN** the layout follows the posture, and the reader avoids placing a page's focal area across the hinge

#### Scenario: Orientation
- **WHEN** the device rotates
- **THEN** the reader keeps the current page, the library keeps its scroll position, and the current destination does not change

#### Scenario: A layout the window is too small for
- **WHEN** a window is too narrow for a two-pane layout the app would otherwise use
- **THEN** it falls back to a single pane showing what the reader was looking at, rather than showing a truncated pane or an empty one
- **AND** widening the window again restores the second pane without losing position
