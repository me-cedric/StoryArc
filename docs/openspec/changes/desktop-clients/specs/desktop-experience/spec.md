## Purpose

What a reader sees and does when StoryArc runs on a macOS, Windows or Linux desktop: windows, menus,
keys, a pointer, files dropped on the app, and the desktop reading of the mobile terms in the other
capabilities. Every other capability holds on a desktop as written, except where this one says how
its words read there.

## ADDED Requirements

### Requirement: Supported desktop systems

The app SHALL run on macOS 26 and later, on Windows 11 24H2 and later, and on a Linux desktop with
a Wayland or X11 session on Ubuntu 24.04, Pop!_OS 24.04, Fedora 43, Arch Linux and Manjaro or any
release newer than those. It SHALL run natively on both Intel-class and Arm-class processors where
the platform ships both.

#### Scenario: A supported system
- **WHEN** a reader installs the app on a supported release
- **THEN** it opens, shows the library and reads a publication with no manual setup beyond what the install documents

#### Scenario: A system below the floor
- **WHEN** a reader tries to install or start the app on a macOS or Windows release below the floor
- **THEN** the system's own installer or launcher refuses the app, so the app never opens a library it cannot draw

#### Scenario: A Linux build below the floor
- **WHEN** a reader builds or starts the app on a Linux system whose GTK or libadwaita is older than the floor
- **THEN** the build or the start fails and names the missing GTK or libadwaita version
- **AND** the app does not open a library it cannot draw

#### Scenario: A Linux system without an optional service
- **WHEN** the app starts on a Linux session that has no file chooser service, no secret store or no dark-mode setting
- **THEN** it still opens and reads
- **AND** each missing service is named once, in grey, where its feature is used, with the package that supplies it

### Requirement: A desktop interface in each system's own idiom

On each desktop the app SHALL use that system's own interface conventions, controls, title bar, menus and
dialogs, and SHALL NOT draw a shared interface across systems. The artwork SHALL remain the interface:
chrome is for navigation and never competes with a cover or a page.

#### Scenario: Native look on each system
- **WHEN** the library is shown on macOS, on Windows and on Linux
- **THEN** each looks like an application of its own system, with its own sidebar, title bar, dialogs and context menus
- **AND** no control copies another system's look

#### Scenario: Chrome material follows the system
- **WHEN** the system draws translucent window material and the reader has not turned transparency off
- **THEN** the library's toolbar and sidebar use that material
- **AND** a cover or a page is never drawn behind translucent material that lowers its legibility

#### Scenario: Transparency off
- **WHEN** the reader has turned transparency off, or increased contrast on, in the system
- **THEN** the same chrome is drawn opaque
- **AND** every label stays legible and no information is lost

#### Scenario: A system without translucent material
- **WHEN** the system offers no translucent material, as on a Linux desktop
- **THEN** the chrome is drawn opaque
- **AND** the reader sees no gap or placeholder where material would have been

### Requirement: The interface accent and the system appearance

The app SHALL follow the system light and dark appearance while it runs, and SHALL change it without a restart.
The accent of the library chrome SHALL be the StoryArc brand colour by default. The settings SHALL offer a choice to follow the
system accent colour instead, and SHALL offer it only where the system offers an accent colour. A colour taken from a cover
SHALL remain inside the readers.

#### Scenario: The default accent
- **WHEN** a reader has never chosen an accent
- **THEN** the library chrome uses the StoryArc brand colour, whatever accent colour the system has

#### Scenario: Following the system accent
- **WHEN** a reader chooses the system accent colour in the settings
- **THEN** the library chrome takes the system's accent colour at once, with no restart
- **AND** a later change of the system accent recolours the chrome while the app is open, and no window needs to be reopened

#### Scenario: A system with no accent colour
- **WHEN** the system offers no accent colour, as on the oldest Linux releases the app supports
- **THEN** the settings do not show the choice to follow the system accent
- **AND** the library chrome keeps the StoryArc brand colour

#### Scenario: The system switches appearance
- **WHEN** the system changes between light and dark while the app is open
- **THEN** every open window follows within one second and no window needs to be reopened

#### Scenario: A system that does not state its appearance
- **WHEN** the system provides no appearance setting, as on a minimal Linux session
- **THEN** the app uses the light appearance and says nothing alarming
- **AND** the reader can choose an appearance in the app

### Requirement: The window model

The app SHALL show one library window and any number of reader windows. Each reader window SHALL read one
publication. The library SHALL stay open and usable while readers are open.

#### Scenario: Opening a publication
- **WHEN** a reader opens a publication from the library
- **THEN** it opens in a new reader window and the library window stays where it was

#### Scenario: Opening a publication that is already open
- **WHEN** a reader opens a publication that already has a reader window
- **THEN** that window comes to the front and no second window opens for it

#### Scenario: Two publications side by side
- **WHEN** a reader has two reader windows open
- **THEN** each keeps its own page, zoom, theme and chrome state
- **AND** a page turn in one never moves the other

#### Scenario: A reader window whose publication disappears
- **WHEN** the file or source behind an open reader window becomes unreachable
- **THEN** that window keeps the pages it already holds and says in grey that the rest is unavailable
- **AND** other windows are unaffected, and no window closes by itself

### Requirement: Windows come back after a quit or a crash

The app SHALL restore the library window and every reader window to the position, size, display and page they had
when the app last closed or ended.

#### Scenario: Relaunch after a quit
- **WHEN** a reader quits with a library window and two reader windows open and starts the app again
- **THEN** the same three windows open at their previous positions and sizes, each reader on its previous page

#### Scenario: A display that is gone
- **WHEN** a restored window belongs to a display that is no longer connected
- **THEN** it opens fully visible on a display that exists

#### Scenario: A publication that cannot be reopened
- **WHEN** a restored reader window's publication has been removed or its source is offline
- **THEN** that window does not open, the other windows do, and the library names what could not be restored in grey
- **AND** the page position stays in the progress store so the publication resumes when it returns

#### Scenario: The app ended without warning
- **WHEN** the app ended through a crash or a power cut
- **THEN** the windows restore at their last saved state
- **AND** the reading position is no older than the last saved position described under closing and quitting

### Requirement: Closing a window and quitting the app

Closing a window SHALL replace the mobile idea of sending an app to the background. The app SHALL write
reading progress as the reader reads, SHALL write it again before a reader window closes, and SHALL write it again before the app quits.

#### Scenario: Progress while reading
- **WHEN** a reader turns pages
- **THEN** the position is written no later than five seconds after the last turn, and never once per frame

#### Scenario: Closing a reader window
- **WHEN** a reader closes a reader window
- **THEN** the current position is written before the window disappears
- **AND** the library shows that position in Continue reading at once

#### Scenario: Quitting
- **WHEN** a reader quits the app with reader windows open
- **THEN** every open reader's position is written before the process ends

#### Scenario: A write that fails
- **WHEN** the progress write fails, for example because the disk is full
- **THEN** the window still closes and the app still quits
- **AND** the app retries at the next launch from the position it holds in memory or in the restored window state, and names the failure in the diagnostic

#### Scenario: Closing the last window on each system
- **WHEN** a reader closes the last window
- **THEN** on macOS the app stays running with its menu bar, and on Windows and Linux the app quits
- **AND** audio that is playing stops with a quit and continues when the app keeps running

### Requirement: No presence when the app is closed

The app SHALL NOT keep a background process, a tray or status icon, or a notification channel after the reader
quits it. It SHALL NOT post a desktop notification.

#### Scenario: After quitting
- **WHEN** the reader has quit the app
- **THEN** no process of the app remains, no icon of the app stays in a tray or status area, and no sync or download continues

#### Scenario: A download in progress
- **WHEN** the reader quits while a download is in progress
- **THEN** the app says before quitting that the download will pause and resume at the next launch, and quits when the reader agrees
- **AND** the partial file is kept and resumes from where it stopped

#### Scenario: A finished download or a refresh
- **WHEN** a download finishes or a source refreshes while the app runs
- **THEN** the library reflects it, and no desktop notification is posted

### Requirement: Menus, commands and shortcuts

The app SHALL put every command in a menu. On macOS the menus SHALL be in the system menu bar. On Windows and
Linux they SHALL be in the window, in a menu button or a menu bar. The app SHALL give each frequent command a
keyboard shortcut that uses the system's own modifier: Command on macOS and Control on Windows and Linux.

#### Scenario: Every command is in a menu
- **WHEN** a reader opens the menus in the library and in a reader
- **THEN** open file, add a folder, search, preferences, close window, quit, full screen, next and previous page, zoom, go to page and the reader menu entries are all there, each with its shortcut when it has one

#### Scenario: The standard shortcuts
- **WHEN** a reader presses the system modifier with O, F, comma, W, Q or the full-screen key
- **THEN** the app opens a file, focuses search, opens preferences, closes the window, quits or toggles full screen, as the menu entry says
- **AND** on Linux, where the system has no standard Quit key, Control and Q quits and Control and W closes the window
- **AND** on Windows, Control and W closes the window, the File menu holds Quit with no key of its own, and Alt and F4 closes the window

#### Scenario: A command that does not apply
- **WHEN** a command cannot apply, for example Next page in the library
- **THEN** its menu entry is shown disabled and not removed, so the menu has the same shape in every window

#### Scenario: A shortcut while typing
- **WHEN** a reader types in a text field, such as search
- **THEN** a letter or arrow key edits the text and does not turn a page
- **AND** a shortcut that uses the system modifier still works

#### Scenario: A shortcut another application holds
- **WHEN** the system or another application already uses a shortcut the app declares
- **THEN** the menu entry stays reachable by pointer and keyboard navigation and the app does not fail

### Requirement: Full keyboard navigation

A reader SHALL be able to do everything the app offers with the keyboard alone. Focus SHALL always be visible and
SHALL never be trapped.

#### Scenario: Tabbing through the library
- **WHEN** a reader presses Tab in the library
- **THEN** focus moves through the sidebar, the toolbar, the search field and the publications in reading order, and a visible ring shows where it is
- **AND** Shift and Tab moves backwards through the same order

#### Scenario: Acting on a focused item
- **WHEN** a publication has focus and the reader presses Return, Space or the context menu key
- **THEN** it opens, selects, or opens its menu, as the platform's own lists do

#### Scenario: Leaving a book's text
- **WHEN** focus is inside a book's text and the reader presses Escape or Tab
- **THEN** focus moves to the reader's chrome and never stays inside the text
- **AND** the same key sequence moves focus back into the text

#### Scenario: A dialog
- **WHEN** a dialog opens
- **THEN** focus moves into it, Escape closes it, and focus returns to the control that opened it

### Requirement: Keys that turn pages

In a reader, the arrow keys, Page Up, Page Down, Space and Home and End SHALL move through the publication. The
horizontal keys SHALL follow the reading direction.

#### Scenario: Left-to-right
- **WHEN** a reader presses the right arrow, Page Down or Space in a left-to-right publication
- **THEN** the next page shows
- **AND** the left arrow and Page Up show the previous page

#### Scenario: Right-to-left
- **WHEN** a reader presses the right arrow in a right-to-left publication
- **THEN** the previous page shows, so the key points the way the page moves
- **AND** Page Down and Space still show the next page

#### Scenario: A key at the end
- **WHEN** a reader presses the next-page key on the last page
- **THEN** the page does not move and the app opens the next publication only where the reader has asked it to
- **AND** nothing is announced as an error

#### Scenario: A key held down
- **WHEN** a reader holds the next-page key
- **THEN** pages turn at the rate the system repeats the key, and the app does not queue turns that outlast the key

### Requirement: Search on a desktop

Search SHALL be a field that stays in the toolbar or the header on every desktop, and activating it SHALL show a
results view that takes over the content column. The field SHALL still be there after search opens. This is the
desktop reading of the navigation-shell requirement Reaching search, which holds as written.

#### Scenario: Opening search
- **WHEN** a reader presses the system modifier and F, or clicks the search field
- **THEN** the field takes focus without changing its shape or position, and the results view replaces the content column while text is in the field

#### Scenario: Leaving search
- **WHEN** a reader clears the field or presses Escape
- **THEN** the content column returns to the destination the reader came from, and the field is still in place

### Requirement: Pointer reading

In a reader the pointer SHALL replace touch. Moving the pointer SHALL reveal the chrome. The chrome and the
pointer SHALL hide after the pointer rests, and a context menu SHALL be available on a right click.

#### Scenario: Revealing chrome
- **WHEN** the pointer moves inside a reader window
- **THEN** the chrome appears
- **AND** after the pointer rests for three seconds the chrome and the pointer hide, and the page does not move

#### Scenario: A context menu
- **WHEN** a reader right-clicks a page, a publication in the library, or a collection
- **THEN** a menu offers the actions the long press offers on a phone for that item

#### Scenario: Edge click zones
- **WHEN** a reader clicks the leading or trailing edge of a page
- **THEN** the page turns only where the zones are on, and the zones are on by default
- **AND** a reader can turn the zones on or off in the reader's settings, and with the zones on a click on the leading or trailing edge turns the page, with a click in the middle toggling the chrome

#### Scenario: Selecting text and moving the window
- **WHEN** a reader drags across text in a book, or drags the title bar
- **THEN** the drag selects text or moves the window and never turns a page

#### Scenario: A pointer that is not there
- **WHEN** the machine has no mouse and no trackpad
- **THEN** every action a pointer offers is reachable by the keyboard

### Requirement: Zoom and pan with a pointer

In a comic or PDF reader, a reader SHALL be able to zoom with a trackpad pinch, with the system modifier held
and the wheel turned, with a double click, and with keyboard keys. A zoomed page SHALL pan by scroll or by drag.

#### Scenario: Pinch and wheel
- **WHEN** a reader pinches on a trackpad, or holds the system modifier and turns the wheel, over a page
- **THEN** the page zooms around the pointer and stays inside the limits the reader has for touch

#### Scenario: Double click
- **WHEN** a reader double-clicks a page
- **THEN** it zooms to the same level a double tap gives on a phone, and a second double click fits the page again

#### Scenario: Plain wheel on a page that fits
- **WHEN** a reader turns the wheel over a page that is fitted and not zoomed
- **THEN** the wheel turns the page in a paged reader, and scrolls the strip in a scrolling reader

#### Scenario: Zoom keys and the limits
- **WHEN** a reader presses the system modifier with plus, minus or zero
- **THEN** the page zooms in, zooms out or fits, and a key beyond a limit does nothing and says nothing

### Requirement: Dragging to turn a page

A reader SHALL be able to turn a page by dragging with the pointer or by swiping on a trackpad, and a page
curl SHALL follow the pointer where the curl is available.

#### Scenario: A drag past the threshold
- **WHEN** a reader drags a page past the distance that commits a turn and releases it
- **THEN** the page turns in the direction of the drag, mirrored in a right-to-left publication

#### Scenario: A drag short of the threshold
- **WHEN** a reader releases a drag before it commits
- **THEN** the page settles back and no turn is counted

#### Scenario: The curl follows the pointer
- **WHEN** the transition mode is the curl and a reader drags
- **THEN** the curl follows the pointer without a visible lag, at the display's own refresh rate

#### Scenario: The curl where it is not available
- **WHEN** the curl is unavailable on this system, or the system asks for reduced motion
- **THEN** the reader's mode shows as the nearest mode that is available, and the settings say why the curl is absent in grey
- **AND** the page still turns by drag, key and wheel

### Requirement: Two-page spreads by window shape

A comic reader SHALL show two pages side by side when the window is wide enough, and one page when it is not.
The pairing offset and the reading direction SHALL decide the pairs.

#### Scenario: A wide window
- **WHEN** a reader widens a reader window past the width at which two pages fit
- **THEN** two pages show side by side with the cover alone on the first screen, and a page that is already a double spread shows alone and full width

#### Scenario: A narrow window
- **WHEN** a reader narrows the window below that width, or tiles it into a narrow column
- **THEN** one page shows, on the same page the reader was on

#### Scenario: The last page of an odd count
- **WHEN** the last page has no partner
- **THEN** it shows alone, centred, and no blank page is drawn beside it

#### Scenario: A page that has not loaded
- **WHEN** one page of a pair is still decoding or cannot be read
- **THEN** the other page shows at once and the missing one is a quiet placeholder, never a spinner over the artwork

### Requirement: Full screen reading

A reader window SHALL be able to enter full screen, where only the page shows until the reader asks for chrome.

#### Scenario: Entering and leaving
- **WHEN** a reader presses the full-screen key or chooses it in the menu
- **THEN** the window fills the display, the system menu bar or title bar hides, and only the page remains
- **AND** Escape or the same key leaves full screen and restores the window's size

#### Scenario: Chrome in full screen
- **WHEN** the pointer moves in a full-screen reader
- **THEN** the reader's chrome appears and then hides as in a window

#### Scenario: A system that refuses
- **WHEN** the system or the window manager does not grant full screen, as in some tiling layouts
- **THEN** the window stays as it is, reads normally, and the menu entry says in grey that full screen is not available

### Requirement: Dropping files and folders on the app

The app SHALL accept a file or a folder dropped on its windows or on its icon.

#### Scenario: Dropping a publication
- **WHEN** a reader drops one supported file on the library window, on a reader window or on the app icon
- **THEN** it opens in a reader window as an opened file does, and is remembered under recent items

#### Scenario: Dropping a folder
- **WHEN** a reader drops a folder on the library window
- **THEN** the app offers to add it as a folder library and adds it only when the reader agrees

#### Scenario: Dropping several files
- **WHEN** a reader drops several supported files at once
- **THEN** each opens in its own reader window up to a limit the app names, and the rest are listed so the reader can open them from the library

#### Scenario: Dropping what cannot be opened
- **WHEN** a reader drops a file of a format the app does not read, or a file that is damaged, or a CB7 archive
- **THEN** the app refuses that file by name with the reason, in the place where What could not be opened is shown
- **AND** the files dropped with it that can be read still open

#### Scenario: A drop that is not a file
- **WHEN** a reader drops text or an image that is not a file
- **THEN** nothing happens and no error appears

### Requirement: File associations and Open With

A reader SHALL be able to open a publication from the system's file manager by double click, by Open With, by
the command line, and by dropping it on the icon.

#### Scenario: Double click while the app is not running
- **WHEN** a reader double-clicks a supported file and the app is not running
- **THEN** the app starts and the file opens in a reader window, without opening the library window in front of it

#### Scenario: Double click while the app is running
- **WHEN** a reader opens a second file while the app is running
- **THEN** the running app opens it in a new reader window and no second copy of the app starts

#### Scenario: The command line
- **WHEN** the app is started from a terminal with a path as its argument
- **THEN** it opens that publication, and with several paths it opens each, as dropping several files does

#### Scenario: A file that cannot be reached
- **WHEN** a reader opens a file that has been moved, deleted or is on an unmounted volume
- **THEN** the app names the file and the reason in grey and opens nothing else

#### Scenario: Recently opened files
- **WHEN** a reader opens a file
- **THEN** it joins the list of recent items, and a file that no longer exists drops out of the list without an error

### Requirement: Choosing folders and keeping access

A reader SHALL add a folder library by choosing it in the system's own folder chooser. Access to a chosen
folder SHALL survive a relaunch without asking again.

#### Scenario: Adding a folder
- **WHEN** a reader chooses a folder
- **THEN** it becomes a source and its publications appear in the library

#### Scenario: Access across relaunches
- **WHEN** the app is quit and started again
- **THEN** every chosen folder is readable without a second prompt

#### Scenario: Access withdrawn
- **WHEN** the system or the reader has withdrawn the app's access to a folder
- **THEN** the source shows in grey as needing access, keeps its place in the library, and offers one action to choose the folder again
- **AND** the publications already downloaded or cached stay readable

#### Scenario: A folder on an unmounted volume
- **WHEN** a chosen folder is on a volume that is not connected
- **THEN** the source shows as offline, in grey, and returns by itself when the volume does

### Requirement: Live folder watching

While the app runs, it SHALL notice files added, removed or renamed in a watched folder without a manual refresh.

#### Scenario: A file added while the app is open
- **WHEN** a file is copied into a watched folder while the app runs
- **THEN** it appears in the library within 10 seconds

#### Scenario: The system cannot watch more
- **WHEN** the system's limit on watched folders is reached, or a folder is on a network share that reports no changes, or a folder is granted through a portal that passes no change events, as a sandboxed Linux package receives it
- **THEN** the app rescans the folder when its window gains focus and at a fixed interval of 10 seconds or less that the app states, and offers a refresh action
- **AND** it says once, in grey, that this folder is not watched live

#### Scenario: Changes while the app was not running
- **WHEN** the app starts after files changed in a watched folder
- **THEN** it reconciles by modification time and size and does not read every archive again

#### Scenario: A burst of changes
- **WHEN** thousands of files change at once, as when a folder is synchronised
- **THEN** the library updates in batches and the window stays responsive

### Requirement: Secrets in the system's own store

The app SHALL keep every credential in the secure store the operating system provides and nowhere else. It SHALL
never write a secret to a file, a preference, a log, a backup or an export.

#### Scenario: Saving a password
- **WHEN** a reader enters a password, a token or an API key for a source
- **THEN** it goes to the system's secure store, and the source's own record holds only a reference

#### Scenario: A secure store that is not running
- **WHEN** the system has no secure store available, as on a minimal Linux session
- **THEN** the app does not save the secret, and says once, in grey, that none is available and what supplies one
- **AND** the source works for the rest of the session with the secret held in memory, and asks again at the next launch

#### Scenario: A secret the store refuses
- **WHEN** the store rejects a write, or a reader denies its prompt
- **THEN** the app names the failure and keeps no copy, and the source shows as needing a sign-in

#### Scenario: Searching the app's files
- **WHEN** the app's data directory, its logs and an exported diagnostic are searched for a known secret
- **THEN** none of them holds it, in any encoding

### Requirement: Keeping the display awake while reading

While a reader window is in front, the app SHALL stop the display from sleeping and SHALL stop the system from
idling into sleep while audio plays. It SHALL release both as soon as the reason ends.

#### Scenario: Reading in front
- **WHEN** a reader window is in front and the reader reads
- **THEN** the display does not sleep because of inactivity
- **AND** the display may sleep again within the system's normal delay once the window is closed, hidden or no longer in front

#### Scenario: Listening
- **WHEN** an audiobook or read-aloud plays with every window hidden or in the background
- **THEN** the system does not idle into sleep while it plays, and may once playback stops or pauses

#### Scenario: A system that cannot be asked
- **WHEN** the system refuses the request or has no service that grants it
- **THEN** reading and listening continue as usual and the app says nothing alarming

### Requirement: Metered connections

The app SHALL treat a connection the system marks as metered like the cellular connection on a phone. A
connection the system does not describe SHALL be treated as not metered.

#### Scenario: A metered network
- **WHEN** the system reports the active connection as metered
- **THEN** the downloads policy that says "Wi-Fi only" holds back downloads that the reader has not asked for by hand, and the queue says in grey why they wait
- **AND** a reader can still start a download by hand and the app starts it

#### Scenario: A network that is not metered
- **WHEN** the connection is not metered or the system does not say
- **THEN** downloads run as the policy says for an unmetered network

#### Scenario: A network that changes mid-download
- **WHEN** the connection changes to a metered one while a download runs
- **THEN** the app pauses the downloads the policy holds back and resumes them when an unmetered connection returns

#### Scenario: No connection
- **WHEN** no connection exists
- **THEN** the library and every downloaded publication read normally, and the queue waits in grey

### Requirement: Exporting a diagnostic to a file

On a desktop the diagnostic export SHALL be saved to a file the reader names, in place of a share sheet. The
export SHALL hold what the mobile export holds.

#### Scenario: Saving the diagnostic
- **WHEN** a reader chooses to export diagnostics
- **THEN** the export is shown in full, a save dialog asks where to put it, and a file is written there
- **AND** every credential, token and server hostname is redacted as on a phone

#### Scenario: A place the file cannot be written
- **WHEN** the reader picks a location that cannot be written
- **THEN** the app says so by name and offers another location, and writes nothing elsewhere

#### Scenario: Cancelling
- **WHEN** the reader cancels the save dialog
- **THEN** no file is written and the diagnostic is not kept

### Requirement: Media keys and system media controls

Audiobooks and read-aloud SHALL answer the keyboard's media keys, and SHALL appear in the system's own media
controls with the title, the cover and the position.

#### Scenario: Media keys
- **WHEN** a reader presses play or pause, next or previous on the keyboard, a headset or a Bluetooth device while the app is playing or has played
- **THEN** playback pauses or resumes, or moves to the next or the previous chapter

#### Scenario: The system overlay
- **WHEN** playback starts
- **THEN** the system's media controls show the publication's title, its cover and its position, and a seek in them moves the playback
- **AND** when playback ends or the app quits the entry leaves the controls

#### Scenario: Another application holds the keys
- **WHEN** another application has taken the media keys
- **THEN** the app does not fight for them and its own on-screen controls keep working

#### Scenario: A device with no speech engine
- **WHEN** the system offers no speech engine for read-aloud
- **THEN** the read-aloud control is absent and nothing says it failed, as on a phone

#### Scenario: The windows are hidden
- **WHEN** every window is minimised or hidden and the app keeps running
- **THEN** playback continues and the media keys and system controls still control it

### Requirement: Screen readers on each system

The app SHALL be usable with VoiceOver on macOS, Narrator on Windows and Orca on Linux. Every control SHALL
state a name, a role and its current state.

#### Scenario: Controls in the library
- **WHEN** a screen reader reads the library
- **THEN** each publication is announced with its title, its progress and its source, and each toolbar control with its name and role, never with a raw identifier

#### Scenario: A page turn
- **WHEN** a reader turns a page with a screen reader running
- **THEN** the new page's position is announced, for example page 12 of 180, with the page's text when the publication holds a text layer

#### Scenario: A page with no text
- **WHEN** a page is only an image
- **THEN** it is announced by its position and by the alternative text the publication supplies, and nothing else is invented

#### Scenario: What could not be opened
- **WHEN** a publication or a source cannot be opened
- **THEN** the screen reader announces the same named reason the screen shows

#### Scenario: Orca without an accessibility bus
- **WHEN** the Linux session offers no accessibility service
- **THEN** the app runs as usual and does not fail

### Requirement: Text size, contrast and motion follow the system

The app SHALL follow the system's text scaling, contrast and reduced-motion settings. On macOS, which has no system
text scaling, the reader's own size controls SHALL meet the same need.

#### Scenario: A larger text size
- **WHEN** the reader raises the system text scale on Windows or Linux, or the app's own size control on macOS, to its largest value
- **THEN** every label in the library, the settings and the reader chrome stays readable, wraps or truncates with an accessible full text, and no control moves off the window

#### Scenario: Increased contrast
- **WHEN** the system asks for increased contrast
- **THEN** chrome borders, focus rings and text meet the contrast the system's own controls meet

#### Scenario: Reduced motion
- **WHEN** the system asks for reduced motion
- **THEN** page transitions, zooms and the chrome's appearance use no sliding or curling, and the curl is off

### Requirement: Any window size

A window SHALL stay usable at every size the window manager can give it, down to a documented minimum. Layout
SHALL follow the window's width and height and never the device class.

#### Scenario: A narrow window
- **WHEN** a window is tiled or dragged below the width at which the sidebar and the list sit side by side
- **THEN** the sidebar collapses into a control that opens it, and the list takes the width

#### Scenario: A wide window
- **WHEN** a window is widened
- **THEN** the library adds columns and the publication page uses the large-screen layout, and the sidebar is permanent

#### Scenario: A window below the minimum
- **WHEN** a window manager gives the window less than the minimum
- **THEN** the content scrolls and clips and never overlaps, and the close action remains reachable by keyboard

#### Scenario: Resizing a reader
- **WHEN** a reader window is resized while a page is showing
- **THEN** the page refits at once, keeps the reader's place, and never re-opens the publication

### Requirement: Linux display servers and tiling compositors

On Linux the app SHALL run on Wayland first and on X11 as well. On a tiling compositor, including Hyprland, it
SHALL accept any window size, SHALL stay reachable without a title bar of its own, and SHALL carry a stable
application identity so a user can write window rules for it.

#### Scenario: A Wayland session
- **WHEN** the app starts on a Wayland session
- **THEN** it uses Wayland, scales correctly on a fractional-scale display, and reads at the display's own refresh rate on each monitor

#### Scenario: An X11 session
- **WHEN** the app starts on an X11 session
- **THEN** it opens and reads with every feature except those this requirement names
- **AND** the page curl is absent and the reader's settings say so in grey, until the Linux curl spike shows that it holds the frame budget on X11, and it is present on X11 from then on

#### Scenario: A compositor that draws no title bar
- **WHEN** the compositor answers that it draws the window decorations and draws none, as Hyprland does
- **THEN** the app still shows its header with its menu and a close control, and Control and W closes the window and Control and Q quits

#### Scenario: A stable identity
- **WHEN** a user writes a window rule for the app
- **THEN** the window's class and application identifier are the same on every launch, and every reader window carries the same identifier

#### Scenario: A tiled window of any size
- **WHEN** a tiling compositor gives the window a size from a narrow column to a full display
- **THEN** the layout follows the size under the any-window-size requirement and never fixes a size of its own

#### Scenario: A missing portal
- **WHEN** the session has no file chooser or settings portal
- **THEN** the app opens, names the missing service once in grey where the feature is used, and offers a way to open a file by drop or by command line

### Requirement: Covers in the system's file views

A supported publication SHALL show its own cover as its thumbnail in the system's file manager and in the
system's quick look. On Linux this holds for a source or AUR build: a Flatpak build does not export a thumbnailer to the
host file manager and shows the system's generic icon.

#### Scenario: A file manager thumbnail
- **WHEN** a reader browses a folder of publications in the system's file manager
- **THEN** each supported publication shows its cover as its thumbnail

#### Scenario: A publication with no cover
- **WHEN** a publication has no cover, or is damaged
- **THEN** the system's own generic icon shows and no error is raised in the file manager

#### Scenario: No hand-off of data
- **WHEN** a thumbnail is made
- **THEN** it is made on the device, nothing is sent anywhere, and no reading history is written

### Requirement: Recent items in the system's launcher

The app SHALL list the reader's recent publications in the system's own launcher menu where the system lets an
app name them: the Dock menu on macOS and the Jump List on Windows. On Linux a desktop entry cannot name a
publication, so the app SHALL record each opened publication with the desktop's recent-files service and SHALL
offer the static actions Continue Reading, Library and Downloads in the desktop entry.

#### Scenario: Recent publications
- **WHEN** a reader opens the launcher menu of the app
- **THEN** it lists the last publications read, newest first, and choosing one opens it in a reader window

#### Scenario: A publication that is gone
- **WHEN** a recent publication has been deleted or its source removed
- **THEN** it does not appear in the list, and no error shows

#### Scenario: Recent publications on Linux
- **WHEN** a reader opens a publication on Linux
- **THEN** the app records it with the desktop's recent-files service, and file managers and file dialogs list it
- **AND** the desktop entry offers Continue Reading, Library and Downloads as static actions, and names no publication, because a sandboxed package cannot rewrite its own exported entry

#### Scenario: Clearing the history
- **WHEN** a reader clears their reading history in the app
- **THEN** the launcher list is cleared at once, on Linux the app removes its entries from the recent-files service, and the app writes nothing new to it until a publication is opened

#### Scenario: A launcher with no menu
- **WHEN** the system's launcher offers no such menu
- **THEN** the library's Continue reading still shows the same publications

### Requirement: Opening a link or a command

A link in the app's own address scheme SHALL open one publication or one source in a window.

#### Scenario: A link to a publication
- **WHEN** a reader follows a link of the app's own scheme that names a publication the app holds
- **THEN** it opens in a reader window

#### Scenario: A link to nothing
- **WHEN** the link names a publication or a source the app does not hold
- **THEN** the app names what it could not find in grey and changes nothing

#### Scenario: A link carrying a command
- **WHEN** a link carries anything other than a name to open
- **THEN** the app ignores the rest and changes no setting and no data

### Requirement: Continuing from an iPhone and finding from the system (macOS)

On macOS, a publication a reader has open on an iPhone SHALL be offered for continuing on the Mac, and the
system search SHALL find the titles in the library.

#### Scenario: Continuing from the phone
- **WHEN** a reader reads a publication on an iPhone signed in to the same system account and the Mac is nearby
- **THEN** the Mac offers to continue it and opens it at the position the Mac holds, from its local store or from library sync, once the Mac holds or can reach the publication
- **AND** the Mac never reads a position from the phone itself, so the native-experience scenario that neither platform carries the reading position between devices stays true

#### Scenario: A publication the Mac does not hold
- **WHEN** the continued publication is not available to the Mac
- **THEN** the Mac says so in grey and opens nothing

#### Scenario: Searching from the system
- **WHEN** a reader searches the system for a title in the library
- **THEN** the result opens that publication, and clearing the reading history removes the entries from the system's index

### Requirement: Preferences in their own window

The app SHALL show its settings in a preferences window opened by the system's preferences shortcut and by the
menu, and the window SHALL be searchable.

#### Scenario: Opening the preferences
- **WHEN** a reader presses the system modifier and comma, or chooses Preferences in the menu
- **THEN** a preferences window opens, and a second press focuses the same window rather than opening another

#### Scenario: Searching the preferences
- **WHEN** a reader types a word in the preferences search
- **THEN** only the settings that match show, grouped under their sections, and an empty result says so in grey

#### Scenario: Preferences while a reader is open
- **WHEN** the preferences window is open and a reader window is in front
- **THEN** a change to a reading setting applies to the open reader at once

### Requirement: Language follows the system

The app SHALL show its interface in the languages the localization capability lists. On macOS the reader MAY
choose a language for the app alone. On Windows and Linux the app SHALL follow the system's language list.

#### Scenario: A supported language
- **WHEN** the system's language is one of the supported four
- **THEN** every string in the app, the menus, the dialogs and the file associations' names appear in it

#### Scenario: An unsupported language
- **WHEN** no language in the system's list is supported
- **THEN** the app uses English and never shows a key or a blank

#### Scenario: A long translation
- **WHEN** the longest supported translation is used at the largest text size
- **THEN** no menu, button or label is cut off in a way that hides its meaning, in the menus and the dialogs as well

### Requirement: The same formats on every desktop

Every format the app reads on a phone SHALL read on every desktop, with the same refusals.

#### Scenario: The formats
- **WHEN** a reader opens CBZ, CBR, CBT, EPUB, PDF or an audiobook on macOS, Windows or Linux
- **THEN** it opens, in the same order of pages, with the same cover and the same metadata

#### Scenario: A CB7 archive
- **WHEN** a reader opens a CB7 archive
- **THEN** it is refused by name on every desktop, as on a phone

#### Scenario: An image the system cannot decode
- **WHEN** a page is in a format the system's own codecs cannot decode
- **THEN** the app still shows it when its own decoders can, and otherwise shows a quiet placeholder with a named reason
- **AND** no page in a supported archive decodes on one desktop and not on another

#### Scenario: A large publication
- **WHEN** a reader opens a publication of several hundred megabytes from a network share
- **THEN** the first page shows without reading the whole file and the reader never waits behind a full transfer

### Requirement: A book stays off the network on every desktop

On each desktop, a book's content SHALL never reach the network. A link inside a book SHALL open in the reader's
default browser and never inside the page.

#### Scenario: A book that tries to load a remote resource
- **WHEN** a book references a remote image, a remote script, a remote stylesheet or a remote font
- **THEN** nothing is fetched, the book shows without that resource, and the reader is not asked

#### Scenario: A link to the web
- **WHEN** a reader activates an external link in a book
- **THEN** the system's default browser opens that address and the book stays where it was

#### Scenario: A link inside the book
- **WHEN** a reader activates a link to another place in the same book
- **THEN** the reader moves there and a way back to the previous place is offered

#### Scenario: Proof on each desktop
- **WHEN** a page of eight different attempts to reach the network is opened as a book on each desktop
- **THEN** none of the eight attempts arrives anywhere, as the mobile proof records

### Requirement: Finding and reaching a network share

On a desktop the app SHALL find network shares where the system lets it, and SHALL always offer to enter one by
hand. It SHALL name why a share cannot be reached.

#### Scenario: Discovery that the system offers
- **WHEN** the system announces shares on the local network
- **THEN** they are listed as suggestions, and picking one fills in its address

#### Scenario: Discovery the system does not offer
- **WHEN** the system provides no discovery, as can be the case on Windows
- **THEN** the app says so once, in grey, and the address field is the way in

#### Scenario: An old protocol
- **WHEN** a server answers only with the oldest sharing protocol
- **THEN** the app refuses it by name and says which server setting to change, and never falls back to it

#### Scenario: Encryption
- **WHEN** a connection to a share is made
- **THEN** the source states whether the connection is encrypted
- **AND** on a desktop whose SMB client supports encryption, which is Windows and Linux, the app negotiates it where the server requires it
- **AND** on a desktop whose client does not, which is the Mac until the shared SMB package gains it, a server that requires encryption fails to connect and the source names encryption as the reason

#### Scenario: A server that cannot be reached
- **WHEN** the host is unreachable, the share is missing or the sign-in is rejected
- **THEN** each is named separately in grey, and the other sources stay usable

#### Scenario: A laptop that sleeps
- **WHEN** the machine sleeps or its lid closes while a share is open and then wakes
- **THEN** the share reconnects without a prompt and reading resumes

### Requirement: Storage on a desktop

The app SHALL keep its data in the system's per-user locations, SHALL keep downloads and the cover cache out of
any roaming or synchronised folder, and SHALL show what it uses.

#### Scenario: Where the data lives
- **WHEN** a reader looks at storage in the preferences
- **THEN** it shows the size of downloads, covers and the library's records, and each can be cleared on its own
- **AND** nothing the app writes goes to a folder the system synchronises between machines

#### Scenario: A full disk
- **WHEN** a write fails because the disk is full
- **THEN** the app names it, in grey, keeps what it had, and offers to clear a cache

#### Scenario: Removing the app
- **WHEN** a reader removes the app
- **THEN** the system's own uninstall removes the app, and the preferences offer a way to remove the app's data before that

### Requirement: Sync when the app runs

The app SHALL synchronise the library and the reading position while it runs, and SHALL treat start and quit as
the moments the mobile apps call foreground and background.

#### Scenario: At start
- **WHEN** the app starts and the sync folder or the server is reachable
- **THEN** it merges the sync document before it shows Continue reading, and never blocks the window on it

#### Scenario: At quit
- **WHEN** a reader quits the app
- **THEN** it writes the sync document once more if the reading position changed, within five seconds, and quits regardless of the result

#### Scenario: Offline
- **WHEN** the sync location is unreachable
- **THEN** the app reads normally, shows no red state, and syncs when it returns

### Requirement: About names everything that ships

The About window SHALL name the app, its author, that it is free, its version and the licence of every component
that ships in the desktop build.

#### Scenario: The licence list
- **WHEN** a reader opens About and then the licences
- **THEN** every third-party component of that desktop's build is listed with its licence, including native libraries and the components shared between Windows and Linux

#### Scenario: A component with no listed licence
- **WHEN** the build contains a component whose licence is not in the list
- **THEN** the build fails its checks and is not released

#### Scenario: What changed
- **WHEN** the app starts for the first time after an update from any channel
- **THEN** it shows what changed in this version once

### Requirement: Cold start and responsiveness on a desktop

The app SHALL feel immediate on a desktop. The library window SHALL appear before any source answers.

#### Scenario: Cold launch
- **WHEN** the app is launched cold on a mid-range laptop of the last four years, with a library of 5,000 publications
- **THEN** the library is interactive within 1 second

#### Scenario: Resizing and scrolling
- **WHEN** a reader resizes a window or scrolls a library of 10,000 publications
- **THEN** the frame rate holds at the display's own refresh rate and a dropped frame is a defect

#### Scenario: A source that is slow or offline
- **WHEN** a source is slow or offline
- **THEN** the library shows what it holds with grey placeholders and never shows a blocking spinner

### Requirement: Visual proof of interface changes on a desktop

A change to a desktop screen SHALL carry captures of it on that desktop, in light and dark and at the default and
the largest text size, taken with a control on the same screen at the same moment.

#### Scenario: A change to a screen
- **WHEN** a change alters a desktop screen
- **THEN** its captures for that desktop show light and dark at the default and the largest text size, and a control capture shows the evidence can differ

#### Scenario: A Linux change
- **WHEN** a change alters a Linux screen
- **THEN** it is captured on GNOME, on KDE Plasma, on Hyprland and on COSMIC, and the captures state the session type of each

#### Scenario: A system that cannot be captured
- **WHEN** a desktop or a compositor in the matrix is not available to the author
- **THEN** the change says which row is missing and that its result is not proved, and never reuses another row's capture
