## MODIFIED Requirements

### Requirement: Resuming

The app SHALL make returning to where the user stopped the shortest path in the
app, and SHALL keep the two verbs a publication answers to distinct: a **resume
affordance** opens the book at the stored position, and a **cover** leads to that
publication's page, whose primary action continues from the same position.

Both are resuming. The difference is that one is an offer to carry on and the
other is an offer to look first, and a reader who chose to look should not be
dropped into the book.

#### Scenario: Continue from a resume affordance
- **WHEN** a reader chooses a partially read publication from Keep reading, or from any other affordance that offers to resume it
- **THEN** it opens at the stored position without an intermediate screen
- **AND** nothing between that affordance and the page they stopped on asks them anything

#### Scenario: Continue from the library
- **WHEN** a reader chooses a partially read publication by its cover — in the library, in a shelf, in search results or in a collection
- **THEN** that publication's page opens, per [`publication-detail`](../publication-detail/spec.md), and its primary action opens the book at the stored position
- **AND** that action states that it will continue rather than start, so the reader knows which of the two will happen before taking it
- **AND** the page is the only thing between the cover and the book: no further screen, prompt or confirmation stands in the way of carrying on

#### Scenario: Restart deliberately
- **WHEN** a user wants to start over
- **THEN** a "Start from the beginning" action is available from the publication's own cover in the library — the same long press that offers to file it in a collection — and it clears progress only after confirmation
- **AND** it is offered only on a publication that has progress to clear, and only on one at a time, because a set of publications has no single beginning to return to
- **AND** it is on that menu because the menu is on every cover on every browse surface, so starting over never needs a screen opened first — and it is never a publication page's primary action, which continues from the stored position
