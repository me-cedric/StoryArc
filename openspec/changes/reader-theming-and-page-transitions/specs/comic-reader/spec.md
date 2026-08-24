## REMOVED Requirements

### Requirement: Reading modes

Retired, not dropped. The transition modes and the curl's behaviour move whole
to [`page-transitions`](../page-transitions/spec.md), because a transition
belongs to the container rather than the content — a comic page and an EPUB page
should turn the same way, and restating the curl in two capabilities guarantees
they drift.

The comic-specific parts of it survive as "Page transitions in the comic reader"
below.

## ADDED Requirements

### Requirement: Page transitions in the comic reader

The comic reader SHALL use the transition engine defined in
[`page-transitions`](../page-transitions/spec.md) — Curl, Slide, Fast fade and
Scroll — and SHALL add only the behaviour that is specific to image pages.

#### Scenario: Mode persistence
- **WHEN** a user changes reading mode for a publication
- **THEN** the choice applies to every publication in the same series
- **AND** a global default applies to publications in series never opened before
- **AND** the comic default is independent of the reflowable default, per [`reading-themes`](../reading-themes/spec.md)

#### Scenario: Continuous scroll
- **WHEN** a user reads in Scroll mode
- **THEN** pages are stitched with no gap by default, with an option to show a separator
- **AND** scroll position is preserved exactly when leaving and returning

#### Scenario: Scroll axis for webtoons
- **WHEN** a publication is a webtoon, or its pages are materially taller than they are wide
- **THEN** Scroll defaults to the vertical axis
- **AND** the axis remains overridable

#### Scenario: Curl over image pages
- **WHEN** a curl runs over a comic page
- **THEN** it uses the already-decoded page directly rather than a re-raster, because the page is an image before the turn begins
- **AND** a double-page spread curls as one surface, not as two independent pages
