## ADDED Requirements

### Requirement: Foldable devices

The app SHALL read on a foldable device as the device's own reading apps do: the page
follows the display the reader is looking at, nothing of value sits on the fold, and the
device opening or closing never loses the reader's place.

#### Scenario: Opening and closing the device
- **WHEN** the reader opens or closes a foldable while a publication is open
- **THEN** the same page is shown on the display that is now in use, at that display's size
- **AND** the reading position, the open sheet or menu, and any playing voice or audiobook are kept

#### Scenario: A page and the fold
- **WHEN** a single page is shown on an open display with a fold that separates two areas
- **THEN** the whole page is shown on one side of the fold, at that side's width, and nothing of the page is under the fold
- **AND** a double-page spread puts its gutter on the fold, one page on each side

#### Scenario: The camera and the fold are not content
- **WHEN** the open display reserves a region for a camera or for the fold
- **THEN** no control and no reading text is placed in that region, and full-bleed artwork may extend under it

#### Scenario: Half-open on a table
- **WHEN** the device is half-open and lies flat on one half
- **THEN** the page is shown on the upright half and the reader's controls on the flat half
- **AND** a page turn is still one tap, one key or one swipe

#### Scenario: Held like a book
- **WHEN** the device is half-open and held upright with the fold vertical
- **THEN** a comic or a paged ebook shows a spread, one page on each half, and the gutter on the fold
- **AND** right-to-left reading keeps its order across the two halves

#### Scenario: The outer display
- **WHEN** the device is closed and the outer display is in use
- **THEN** the app shows its phone layout, and nothing is cut off at the display's narrower edge

#### Scenario: Two apps side by side on the open display
- **WHEN** the reader puts StoryArc beside another app on the open display
- **THEN** the layout reflows to the narrower width as it does on a resized window, and the page and the position are kept
- **AND** the insets on each edge are read separately, because the system places its controls on one side only

#### Scenario: The device cannot report its posture
- **WHEN** the device reports no fold, no posture or no reserved region
- **THEN** the app draws the layout it draws on a flat display of that size, and nothing waits for a posture

#### Scenario: Store listings for foldables
- **WHEN** the app is listed in a store that offers a foldable screenshot slot
- **THEN** the listing carries a screenshot set for the folded and the open display in every language of the listing, taken from the app's own interface
