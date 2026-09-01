import SwiftUI

import EpubReaderFeature
import LibraryFeature
import Persistence
import Playback
import PlayerFeature
import SettingsFeature
import StoryArcCore

/// The four destinations, as the platform's own tab bar.
///
/// Until this existed the iPhone had **no tab bar at all**: `StoryArcApp` put `LibraryView`
/// straight into the `WindowGroup`, so the app was the shelf and everything else was
/// behind chrome on it. `navigation-shell` asks for destinations reachable at any
/// time from one persistent control, and for that control not to grow a row when a reader
/// adds a server. This is that control.
///
/// ## The search role was here, and was removed
///
/// **The argument this comment used to make**, at the head of the list below: *"`Tab(role:
/// .search)` is set apart from the three rather than listed among them — the circular
/// button on the trailing edge — and expands into a field that takes the rest of the bar
/// with it. That is the requirement `navigation-shell` states as 'set apart from them
/// rather than listed among them', and it is one argument."*
///
/// **Why it no longer holds.** The argument was sound about the requirement it quoted, and
/// that requirement is the thing that changed. It named a *control* — "set apart from" —
/// and the control it got does more than sit apart: it morphs the tab into a text field in
/// place, confirmed on a device on 2026-08-31. So the bar changed shape under the reader's
/// thumb, and because there was no screen behind it there was nowhere to land and nothing
/// the app could offer before a letter was typed. `navigation-shell` is now written as an
/// outcome instead: search "SHALL be a place a reader arrives at, and no control SHALL
/// change shape or position to become it".
///
/// **What removing the role costs.** Placement on the trailing edge, the circular
/// treatment, and the morph — all three, and they were genuinely the platform's own work.
/// What it buys is the thing the requirement now asks for: a destination with a screen
/// behind it, drawn like its three neighbours, that leaves the control the reader's thumb
/// is resting on exactly where it was. See ``LibraryDestination`` for why *this* app in
/// particular needs search to be a place rather than a filter.
///
/// **The bar keeps its floating capsule**, which is what iOS 26 draws. Android's
/// deliberately does not — `ShortNavigationBar` exposes no `shape` parameter at all, so a
/// capsule is inexpressible there rather than merely discouraged. That divergence is in the
/// change's `design.md` and is [ADR-0001](../../docs/decisions/0001-independent-native-cores.md)
/// working as intended.
///
/// Three things the system still gives us here that hand-building would not:
///
/// - **`.tabViewStyle(.sidebarAdaptable)`** makes the same set the iPad's sidebar without a
///   second navigation to keep in step, and the adaptation is non-destructive: rotating
///   back does not lose the destination, its scroll position or its filters.
/// - **`.tabBarMinimizeBehavior(.onScrollDown)`** is *"chrome that gets out of the way"* —
///   the bar recedes as covers scroll and comes back on the way up, with no animation when
///   the system asks for reduced motion, and no state in which it cannot be recovered.
/// - **A safe area.** The floating search pill this replaces had none, so cover titles at
///   the foot of the grid rendered *behind* it. A real tab bar insets its content.
///
/// The docked-transport slot below the tabs — `tabViewBottomAccessory`, the mini player in
/// the reference the owner supplied — held this comment's predecessor open and empty for a
/// reason it stated honestly: the only transport this app had was EPUB read-aloud, it lived
/// inside a reader presented as a full-screen cover, and speech ended when that cover was
/// dismissed, so there was no navigation behind it to dock to. `read-aloud-beyond-the-reader`
/// moved the session out of the screen, and `audiobooks-and-playback` moved it again — into
/// `PlayerCentre`, which a narrated audiobook and a synthesised voice both drive. So the slot
/// carries one `PlayerDock` for both. Nothing else is put at that edge; it is the app's one
/// persistent transport, because the platform already offers the rest on the lock screen.
struct AppShell: View {
    /// What a tab is worth as a selection.
    ///
    /// All four destinations come from ``LibraryDestination`` rather than being restated,
    /// so the promise that the set does not grow with what a reader configures is held in
    /// one place and tested there. Search had a `case` of its own here while it was a role,
    /// because a role is not a destination and the shell still had to address its tab; now
    /// that it is a destination, the extra case would be a second way to say the same thing
    /// and a second thing to keep in step.
    enum Selection: Hashable {
        case destination(LibraryDestination)
        /// A row the iPad sidebar reveals below the four. Not a destination and never in
        /// the tab bar — see ``SidebarEntry`` and ``LibrarySidebar``.
        case sidebar(SidebarEntry)
    }

    /// Where the reader is. `navigation-shell`: the app opens on the home surface, unless
    /// the launch named somewhere else.
    @Binding var tab: Selection

    /// What changed in the version just installed, if this launch is the one that says so.
    ///
    /// `settings-and-about`: shown "once, after it has been updated", never on a first ever
    /// launch, and never twice for one version. All three are ``WhatsNew/onLaunch(store:)``'s
    /// answer, and it is asked **here, in the initial value of the state** rather than in a
    /// `.task`: the version is recorded by the same call that decides, so a reader who swipes
    /// the sheet away — or one who never sees it because the version had nothing to say — is
    /// recorded either way. There is no path through this that shows the screen without
    /// recording it, which is the requirement stated as "the seen flag is written when the
    /// screen is shown, not when it is dismissed".
    ///
    /// It is the shell's rather than `StoryArcApp`'s because this is what a reader lands on,
    /// and `design.md` puts the presentation here.
    @State private var whatsNew: WhatsNewRelease? = WhatsNew.onLaunch()
    /// Whether the full player is presented.
    ///
    /// **Held here, by the shell, because the shell is what outlives a session.** It was
    /// `@State` inside `PlayerDock`, which attached the presentation inside
    /// `if let bar = centre.compact` — a computed value that changes on every play/pause and
    /// every chapter boundary, so pressing a transport control inside the player destroyed the
    /// player's own host. `PlayerSheet.swift` in `PlayerFeature` carries the full account.
    ///
    /// The dock still decides *when* to open it; it no longer hosts it.
    @State private var isShowingPlayer = false

    let model: LibraryModel
    let progress: ProgressStore?
    let onOpen: (Publication, URL) -> Void
    let onOpenSettings: () -> Void
    /// See ``LibraryView/init(model:surface:progress:onOpen:showLibrary:)``.
    let showLibrary: Int

    var body: some View {
        // Read in `body`, where Observation registers the dependency, rather than inside
        // the accessory's own builder, which SwiftUI may run later. The narrow question —
        // is a session running — and not the book, whose chapter is rewritten on every
        // sentence: the shell has no business redrawing three times a minute for hours.
        let isPlaying = PlayerCentre.shared.isRunning

        TabView(selection: $tab) {
            Tab(value: .destination(.home)) {
                HomeScreen(
                    model: model,
                    onOpen: onOpen,
                    onOpenSettings: onOpenSettings
                )
            } label: {
                label(Text("tab.home"), LibraryDestination.home.symbolName)
            }

            Tab(value: .destination(.library)) {
                library(.shelf)
            } label: {
                label(Text("tab.library"), LibraryDestination.library.symbolName)
            }

            // Not `library(.onDevice)` any more. That drew the right *set* of covers and
            // nothing else — no queue, no idea what the files weigh, no way to remove one
            // — with the rest of it three taps inside the Settings modal. The destination
            // owns all of it now; see ``DownloadsDestination``.
            Tab(value: .destination(.onDevice)) {
                DownloadsDestination(
                    model: model,
                    onOpen: onOpen,
                    onShowLibrary: { tab = .destination(.library) }
                )
            } label: {
                label(Text("tab.downloads"), LibraryDestination.onDevice.symbolName)
            }

            // **No `role:`.** A fourth tab, drawn like its three neighbours, leading to a
            // page — see this type's own comment for what the role did and why it went. The
            // label was always ours and stays ours: the system would write its own in the
            // *device's* language, and `localization` lets a reader choose the app's without
            // touching the device's.
            Tab(value: .destination(.search)) {
                library(.search)
            } label: {
                label(Text("tab.search"), LibraryDestination.search.symbolName)
            }

            // The iPad's second half of the same set: library sections and the reader's
            // shelves, under their own headers, hidden from the tab bar so the phone still
            // shows four destinations and nothing else.
            LibrarySidebar(model: model, onOpen: onOpen) { Selection.sidebar($0) }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // The docked transport, for everything that speaks. `audio-playback` requires that
        // it reserve no space when there is no session, and ``PlaybackAccessory`` is what
        // holds that promise — see its own comment for why an empty builder is not enough.
        .modifier(
            PlaybackAccessory(
                isPlaying: isPlaying,
                isShowingPlayer: $isShowingPlayer,
                onReturn: onOpen
            )
        )
        // The player itself, hosted here rather than in the accessory above.
        //
        // `audio-playback` asks that opening the player "never restarts, reloads or
        // repositions the audio", and the accessory could not keep that promise: the bar reads
        // the book's chapter, so the bar is rebuilt as the audio moves, and a presentation
        // attached inside it was torn down by its own transport controls. This is attached to
        // the `TabView`, which exists for as long as the app does.
        .playerSheet(isPresented: $isShowingPlayer, centre: .shared)
        // What changed, once, over whatever the reader landed on.
        //
        // `.large` and one detent, because the content is a heading and four rows: a medium
        // detent would show two of them and a drag handle, which reads as a card the reader
        // has to open rather than a thing the app is telling them. `design.md` settles it,
        // and Android's `ModalBottomSheet` is capped and expandable for the reason Material
        // gives there — the two platforms are deliberately not the same shape here.
        //
        // Never blocking: dismissing it needs one action and the tab bar is behind it, not
        // gone. Nothing waits on it and nothing is lost by ignoring it.
        .sheet(item: $whatsNew) { release in
            WhatsNewSheet(release: release) { whatsNew = nil }
                .presentationDetents([.large])
        }
        // `navigation-shell`: leaving search returns the reader to the destination they
        // were on "with its scroll position and filters intact". The query narrows the one
        // library, so a term left behind would follow them onto the shelf and leave it
        // looking half-empty for no reason they could see. The term itself is not lost —
        // the model has already filed it as a recent search.
        .onChange(of: tab) { previous, _ in
            if previous == .destination(.search) { model.query.search = "" }
        }
        // The library is brought up here rather than by whichever surface happens to be
        // shown first. It used to be started by the shelf's own `.task`, which was
        // correct while the shelf *was* the app — and became a bug the moment a reader
        // could land somewhere else: home opened onto an empty library until they had
        // visited the library tab at least once. `home-screen` says home is assembled
        // from what the device already knows, so what the device knows has to be read
        // before home is drawn.
        .task {
            model.restoreFolders()
            await model.refreshProgress()
        }
    }

    /// One tab's label. Named so the four of them cannot drift apart.
    private func label(_ title: Text, _ symbol: String) -> some View {
        Label {
            title
        } icon: {
            Image(systemName: symbol)
        }
    }

    /// The library, on one of its three faces.
    ///
    /// The same view each time, and deliberately: the shelf, the on-device shelf and
    /// search are one screen over three sets, so a cover looks and behaves the same on all
    /// of them and opens the same reader.
    private func library(_ surface: LibrarySurface) -> some View {
        LibraryView(
            model: model,
            surface: surface,
            progress: progress,
            onOpen: onOpen,
            showLibrary: showLibrary
        )
    }
}

/// The slot below the tabs, present only while a voice is speaking.
///
/// **An empty builder is not an absent accessory.** The first attempt passed
/// `tabViewBottomAccessory { if isSpeaking { ... } }`, on the reasoning that producing no
/// content leaves the slot nothing to make room for. A screenshot of the library with no
/// session settled it: the platform draws the glass capsule regardless, so the shelf
/// gained an empty pill above the tab bar and every destination lost that much height.
/// The comment left behind said this was the outcome to watch for and named the remedy,
/// which is the only reason this took one capture rather than an afternoon.
///
/// `tabViewBottomAccessory(isEnabled:)` is that remedy and it is **iOS 26.1** against this
/// app's 26.0 floor ([ADR-0003](../../docs/decisions/0003-platform-floors.md)), so it costs
/// the availability branch below — the app's only one. On 26.0 the empty capsule remains:
/// the old behaviour, not a new defect, and the honest cost of a floor set before the API
/// existed. Delete the branch when the floor moves.
private struct PlaybackAccessory: ViewModifier {
    let isPlaying: Bool
    /// Passed through to the bar, which sets it. The presentation it drives is attached to the
    /// `TabView` above, not inside this accessory — see `PlayerSheet.swift`.
    @Binding var isShowingPlayer: Bool
    let onReturn: (Publication, URL) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isPlaying) { bar }
        } else {
            content.tabViewBottomAccessory {
                if isPlaying { bar }
            }
        }
    }

    /// One slot, one bar, and one session behind it.
    ///
    /// **There were two bars here until `audiobooks-and-playback` §4.2, and the reason is
    /// worth keeping.** A narrated audiobook took the slot through `PlayerDock` and a
    /// synthesised voice took it through a `ReadAloudDock` of its own, because a read-aloud
    /// session driving `PlayerCentre` would have offered a speed control that did nothing —
    /// Readium 3.11.0 sets no rate on an utterance — and `audio-playback` forbids a control
    /// that is "present and refusing". `SpeechRate` and `SpokenVoice` answered that through
    /// the delegate Readium points the caller at, so the second bar went: `design.md` asks
    /// for one session object behind both sources, and two surfaces drawing it was the last
    /// place the two could have disagreed.
    ///
    /// The way back is `onReturn` — the same seam the shelf uses to open a cover, taking the
    /// publication and its URL. Only a publication being read aloud uses it; a narrated
    /// audiobook has no screen to go back to and its row opens the player instead. Opening
    /// the book that is already being spoken is what `SessionHandover` answers with `adopt`:
    /// the reader picks up the sentence the voice is on and the voice never notices.
    private var bar: some View {
        PlayerDock(
            centre: PlayerCentre.shared,
            isShowingPlayer: $isShowingPlayer,
            onReturn: onReturn
        )
    }
}
