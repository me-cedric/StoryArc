public import SwiftUI

internal import DesignSystem
public import Playback
public import StoryArcCore

/// The compact bar, docked with the app's own navigation.
///
/// `audio-playback`: while something is playing "a compact bar rests above the navigation
/// control, naming the publication and the chapter being spoken, and offering play, pause
/// and a way to open the full player" — which on this platform is `tabViewBottomAccessory`,
/// the mini-player slot the shell has held open since `navigation-shell` landed.
///
/// **It lives in the package, and one assumption had to be tested to put it there.**
/// `StoryArcKit` builds for macOS so its pure targets can be tested on the host without a
/// simulator, and `tabViewBottomAccessoryPlacement` looks like an iOS-only API — so this
/// view was written in the app target first. It compiles for macOS, checked by building the
/// package for the host, so it belongs beside the player it opens. That also keeps its words
/// in the player's own catalogue, which `scripts/ios-strings.mjs` checks per module: a bar
/// in the app target would have needed the app's catalogue to carry a second copy of every
/// key the full player already has, and two copies is how "Play" ends up said two ways in
/// French.
///
/// **It states the chapter, not a countdown.** `design.md` records that as the point where
/// the abstraction is thinnest: a narrated file knows its duration and a synthesised voice
/// does not, so the bar says the thing both know. That is why nothing here reads
/// ``PlayerCentre/time``.
///
/// **Plain buttons, never `.glass`.** The accessory slot is already the material, and glass
/// inside glass is the failure `ReadAloudBar`'s own header records — four glass buttons on a
/// glass surface made three of the four glyphs vanish on a device.
///
/// **Focus.** Nothing here moves the screen reader's cursor. `audio-playback`: the bar "does
/// not steal focus when it appears, because a listener who started a book and moved on did
/// not ask to be taken back" — so there is deliberately no `accessibilityFocused` and no
/// screen-changed announcement in this file. The absence is the feature.
public struct PlayerDock: View {
    @Environment(\.theme) private var theme
    /// Full size above the tab bar, or inline in the bar once it has minimised on scroll.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private let centre: PlayerCentre
    /// The way back into a publication being read aloud, which only the app layer can
    /// perform: it owns the full-screen cover the reader is presented in. Handed the
    /// publication and its URL rather than an identifier, so the return opens the same bytes
    /// instead of searching the library for something that looks like them.
    private let onReturn: (Publication, URL) -> Void
    /// Whether the full player is presented — owned by the shell, not by this view.
    ///
    /// **It was `@State` here, and that was the defect.** The `.sheet` was attached inside
    /// ``dock(_:)``, which is reached through `if let bar = centre.compact`; `compact` is
    /// computed and changes on every play/pause and every chapter boundary, so the
    /// presentation's host was destroyed by the action taken inside it. See
    /// ``SwiftUICore/View/playerSheet(isPresented:centre:)``, which is where the presentation
    /// lives now and why it cannot live here.
    ///
    /// This view still *opens* the player — it is the only thing that knows which of its two
    /// ways back applies — it simply no longer hosts it.
    @Binding private var isShowingPlayer: Bool

    public init(
        centre: PlayerCentre,
        isShowingPlayer: Binding<Bool>,
        onReturn: @escaping (Publication, URL) -> Void
    ) {
        self.centre = centre
        self._isShowingPlayer = isShowingPlayer
        self.onReturn = onReturn
    }

    public var body: some View {
        // Read here rather than passed in: the chapter changes as the audio crosses a part,
        // and this is the only view that should redraw when it does.
        if let bar = centre.compact {
            dock(bar)
        }
    }

    private func dock(_ bar: CompactPlayer) -> some View {
        HStack(spacing: StoryArcSpace.sm) {
            wayIn(bar)
            controls(bar)
        }
        .padding(.horizontal, StoryArcSpace.md)
        // One element with its actions reachable separately, which is exactly what
        // `audio-playback` asks for: "announced as one element naming what is playing, with
        // its play/pause action and its open action reachable separately".
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("player.nowPlaying", bundle: .module))
    }

    /// The publication and the chapter, and the whole of it is the way back.
    ///
    /// **Where "back" is depends on the file, and ``CompactPlayer/wayBack`` decides it.** For
    /// a narrated audiobook nothing took the listener away from a screen, so the player is
    /// where the audio is and this opens it. For a publication being read aloud there is a
    /// reader, and `ebook-reader` sends the listener there — "the compact bar is how the
    /// reader gets back to it" — with the player one control to the right, so
    /// `audio-playback`'s "a way to open the full player" is not traded away for it.
    ///
    /// `audio-playback`: "the same source that fed the compact bar feeds this, so opening it
    /// never restarts, reloads or repositions the audio". Nothing here touches the session —
    /// it presents a sheet over the same ``PlayerCentre``, or hands the publication to a
    /// reader that adopts the session rather than starting a second one on the same book.
    private func wayIn(_ bar: CompactPlayer) -> some View {
        Button {
            switch bar.wayBack {
            case .fullPlayer: isShowingPlayer = true
            case .publication: onReturn(bar.book.publication, bar.book.url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(bar.label.title)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textPrimary)
                // The chapter is what has changed since the listener last looked, and the
                // first thing to go when the bar has minimised and there is no room for it.
                if let chapter = bar.label.detail, !isInline {
                    Text(chapter)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The name says where it goes, because a screen-reader user learns the outcome
        // before taking the action rather than after.
        .accessibilityLabel(
            bar.wayBack == .publication
                ? Text("player.back", bundle: .module)
                : Text("player.open", bundle: .module)
        )
        .accessibilityValue(Text(bar.label.detail ?? bar.label.title))
    }

    /// Play, pause, and the way out.
    ///
    /// No scrubber, no speed and no sleep timer: those are the full player's, and a bar
    /// carrying them would be a second set of controls to learn. Skipping is left to the
    /// lock screen and to the player for the same reason the read-aloud dock left it there —
    /// the minimised tab bar is a strip with four destinations already in it.
    ///
    /// **The player's own glyph appears only where the row is not it.** For a narrated
    /// audiobook the row opens the player, and a second control to the same place would be
    /// one more thing in a strip that already holds four destinations. For a publication
    /// being read aloud the row goes to the reader, so the player needs a way in of its own —
    /// `audio-playback` asks the bar for "a way to open the full player" and does not stop
    /// asking because the publication has a page.
    private func controls(_ bar: CompactPlayer) -> some View {
        HStack(spacing: isInline ? StoryArcSpace.xs : StoryArcSpace.sm) {
            if bar.wayBack == .publication, !isInline {
                button("chevron.up", Text("player.open", bundle: .module)) {
                    isShowingPlayer = true
                }
            }

            button(
                bar.isPlaying ? "pause.fill" : "play.fill",
                bar.isPlaying
                    ? Text("player.pause", bundle: .module)
                    : Text("player.play", bundle: .module),
                tint: theme.accent
            ) { centre.toggle() }

            // The way out. A session a listener can start and cannot stop is the failure the
            // whole surface exists to prevent, so this is on both forms of the bar.
            button("stop.fill", Text("player.stop", bundle: .module)) { centre.end() }
        }
        // The words scale and the glyphs do not. At an accessibility text size a capsule
        // this size has one line to give, and it gives it to the title — a bar whose buttons
        // had grown until the book's name was three characters and an ellipsis would be
        // worse for the reader who set that size than for anybody else.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func button(
        _ symbol: String,
        _ label: Text,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                // A glyph is smaller than a finger. Chrome this compact still owes a target
                // somebody can hit while walking.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? theme.palette.textPrimary)
        .accessibilityLabel(label)
    }

    private var isInline: Bool { placement == .inline }
}
