public import SwiftUI

internal import DesignSystem
internal import Playback
public import StoryArcCore

/// The transport that outlives the reader, docked with the app's own navigation.
///
/// `ebook-reader` asks for a control that says what is being spoken, controls it, and
/// returns to it, "carried by the app's own navigation, above it at full size and inline
/// when the navigation is minimised" — which on this platform is `tabViewBottomAccessory`,
/// the mini-player slot the shell has been holding open since `navigation-shell` landed.
///
/// **Why this is not ``ReadAloudBar``.** The two draw the same session and are still two
/// views, because they differ in the one property that cannot be parameterised honestly:
/// the bar floats over a page in the reader's own `GlassEffectContainer` and its buttons
/// are `.glass`; this sits inside a slot the system has *already* made glass, and glass
/// inside glass is the failure `ReadAloudBar`'s own header records — four glass buttons on
/// a glass surface made three of the four glyphs vanish on a device. §3.0 of the UI
/// direction states the same rule as a budget: the accessory is glass, its contents are
/// not. They also differ in what they say (a reader can see which book they are in; a
/// listener three screens away cannot) and in who may see them — this one is `public`
/// because the shell draws it, and the bar has no business being. What they share is the
/// part that would otherwise drift: ``ReadAloudControl``, the five glyphs and five labels.
///
/// **It reserves no space when there is no session.** The shell asks ``ReadAloudCentre``
/// whether one is running and puts nothing in the slot when the answer is no — an accessory
/// with no content, rather than this view rendering empty. See ``AppShell``.
///
/// **Focus.** Nothing here moves the screen reader's cursor. A session can start from the
/// reader and this then appears behind it; `ebook-reader` requires that appearance not to
/// interrupt what a listener is doing, so there is deliberately no `accessibilityFocused`
/// and no screen-changed announcement in this file. The absence is the feature.
///
/// Android draws no counterpart. Its transport is the media notification the session
/// already posts, which survives the app being backgrounded — something a bar inside the
/// app cannot do. Direction §4.9, divergence 2.
public struct ReadAloudDock: View {
    @Environment(\.theme) private var theme
    /// Full size above the tab bar, or inline in the bar once it has minimised on scroll.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// The way back into the book, which only the app layer can perform: it owns the
    /// full-screen cover the reader is presented in. Handed the publication and its URL
    /// rather than an identifier, so the return opens the same bytes instead of searching
    /// the library for something that looks like them.
    private let onReturn: (Publication, URL) -> Void

    public init(onReturn: @escaping (Publication, URL) -> Void) {
        self.onReturn = onReturn
    }

    public var body: some View {
        // Read here rather than passed in: the chapter changes on every sentence, and this
        // is the only view that should redraw when it does.
        if let transport = ReadAloudCentre.shared.transport {
            dock(transport)
        }
    }

    private func dock(_ transport: CompactPlayer) -> some View {
        HStack(spacing: StoryArcSpace.sm) {
            wayBack(transport)
            controls(transport)
        }
        .padding(.horizontal, StoryArcSpace.md)
        // One group, so a screen reader reaches "Read aloud" and then its parts, rather
        // than five loose buttons in the middle of the navigation. `contain` keeps each
        // action addressable, which is the half `ebook-reader` asks for by name.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("readaloud.start", bundle: .module))
    }

    /// The publication and the chapter, and the whole of it is the way back.
    ///
    /// `ebook-reader`: choosing the transport opens the publication "at the sentence being
    /// spoken, without the voice stopping". Nothing here reaches for a locator to do that —
    /// opening the book that is already being spoken is what ``SessionHandover`` answers
    /// with `adopt`, and the reader then picks up the sentence the voice is on. Restarting
    /// it from a position this view had to carry would be a second session on one book.
    private func wayBack(_ transport: CompactPlayer) -> some View {
        Button {
            onReturn(transport.book.publication, transport.book.url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(transport.label.title)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textPrimary)
                // The chapter is what has changed since the listener last looked, and the
                // first thing to go when there is no room for it.
                if let detail = transport.label.detail, !isInline {
                    Text(detail)
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
    }

    /// The same four verbs the reader's own bar offers, and no fifth.
    ///
    /// `ebook-reader`: the transport "never carries a control the media controls do not, so
    /// a listener learns one set of actions" — so there is no scrubber, no speed, no sleep
    /// timer, and no bookmark. A book has no seconds to scrub through anyway.
    ///
    /// Inline keeps play and stop. That placement is the minimised tab bar itself, a strip
    /// with three destinations and a search button already in it, and four more glyphs
    /// there would leave the title no room at all. Skipping a sentence survives one scroll
    /// upwards, and on the lock screen, which is where the platform puts it.
    private func controls(_ transport: CompactPlayer) -> some View {
        let centre = ReadAloudCentre.shared
        return HStack(spacing: isInline ? StoryArcSpace.xs : StoryArcSpace.sm) {
            if !isInline {
                button(.previous) { centre.skip(forward: false) }
            }
            button(.toggle(isSpeaking: transport.isPlaying), tint: theme.accent) {
                centre.toggle()
            }
            if !isInline {
                button(.next) { centre.skip(forward: true) }
            }
            // The way out. A session a listener can start and cannot stop is the failure
            // this whole change is written around, so this is the one control that is on
            // both forms.
            button(.stop) { centre.end() }
        }
        // The words scale and the glyphs do not. At an accessibility text size a capsule
        // this size has one line to give, and it gives it to the title — a transport whose
        // buttons had grown until the book's name was three characters and an ellipsis
        // would be worse for the reader who set that size than for anybody else.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Plain, never `.glass`. See the header: the slot is already the material.
    private func button(
        _ control: ReadAloudControl,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(control.label, bundle: .module)
            } icon: {
                Image(systemName: control.symbol)
            }
            .labelStyle(.iconOnly)
            // A glyph is smaller than a finger. Chrome this compact still owes a target
            // somebody can hit while walking.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? theme.palette.textPrimary)
    }

    private var isInline: Bool { placement == .inline }
}
