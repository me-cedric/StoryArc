## ADDED Requirements

### Requirement: Chrome for a mode a reader is in

When the app puts a reader into a mode — selecting several publications is the one that
exists — the chrome for that mode SHALL take the place of the surface it belongs to rather
than stacking on top of it, and SHALL take each platform's own form for a contextual mode.

A mode is temporary and a reader has to be able to leave it. So the way out SHALL be
present and SHALL NOT be one of the mode's own actions, which are inert until something is
picked.

> **This requirement is written after the behaviour, and that is worth saying.** The
> selection chrome shipped as a full-bleed bar stacked above the tab bar, and nothing in the
> specs made that wrong — `collections-and-reading-lists` says a reader may select in bulk,
> and `native-experience` asks for the platform's conventions in general terms. Neither
> reaches the shape. The owner reported it twice before it was fixed, which is what a missing
> requirement costs.

#### Scenario: The mode replaces its surface rather than stacking on it
- **WHEN** a reader is selecting publications
- **THEN** the mode's actions occupy the place the destination's own primary navigation held, and the two are never drawn at once
- **AND** the actions carry the same material and shape as the chrome they replaced, so the surface still reads as one app — though a platform may change its **tone** to mark the mode, where that platform's convention asks a contextual bar to read as a different bar rather than the same one with different buttons

#### Scenario: How many are chosen, and how to leave
- **WHEN** a selection is running
- **THEN** the number chosen is stated where the surface names itself, not inside the row of actions
- **AND** one action leaves the mode, it is not among the actions that operate on the selection, and it is never disabled

#### Scenario: Nothing chosen yet
- **WHEN** the mode has just been entered and nothing is selected
- **THEN** the actions are present and inert rather than absent
- **AND** an inert action is **drawn** inert, so a reader can tell it apart from a live one without pressing it
- **AND** entering or leaving the mode does not move the content under a reader's thumb mid-gesture

#### Scenario: Each platform's own form
- **WHEN** the mode is drawn on each platform
- **THEN** it follows that platform's convention for a contextual mode rather than a translation of the other's
- **AND** where the two therefore differ, each platform's source says which convention it is following

#### Scenario: Every action names itself
- **WHEN** assistive technology reaches an action in the mode
- **THEN** it is announced by name whatever the action draws
- **AND** an action drawn as a glyph alone is one whose meaning the platform already establishes **on this screen** — a mark another control in the same frame already uses for something else is not established here, whatever it means elsewhere
- **AND** where the width will not hold a name, the action moves into a named menu rather than being reduced to a glyph a reader cannot read, so narrowing costs a reader taps and never meaning
