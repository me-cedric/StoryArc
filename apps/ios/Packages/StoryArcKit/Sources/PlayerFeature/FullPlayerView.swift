public import SwiftUI

internal import DesignSystem
public import Playback
public import StoryArcCore

/// The player behind the compact bar: what is playing, where it is, and everything a
/// listener of a book can do to it.
///
/// `audio-playback`: opening the compact bar shows "the cover, the publication, the chapter,
/// the position and duration, and offers play, pause, skip back, skip forward, a scrub
/// control, the chapter list, playback speed and a sleep timer" — **and** "the same source
/// that fed the compact bar feeds this, so opening it never restarts, reloads or
/// repositions the audio". The second half is why this view holds no engine, no player and
/// no state of its own beyond which sheet is open: it reads ``PlayerCentre`` and writes to
/// it. There is nothing here that *could* restart anything.
///
/// **Where a control is missing rather than disabled.** "Every control the player offers
/// works, or is absent — none is present and refusing." A synthesised voice has no duration,
/// so the scrub control is not drawn at all — not drawn greyed out — and the line under the
/// chapter states which part it is on instead. That is the one branch in this file, and it
/// asks the *time* whether it has a total rather than asking which kind of source is
/// playing.
///
/// It scrolls. `audio-playback` requires that at the largest accessibility text size "the
/// publication, the chapter and every stated value are readable in full, the surface scrolls
/// if it must, and no transport control is pushed off the screen", and a fixed layout is how
/// the transport ends up under the bottom edge.
public struct FullPlayerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let centre: PlayerCentre
    /// What comes after the book that just finished, for the end-of-book offer.
    /// `collections-and-reading-lists` task 7.2. `nil` offers nothing.
    private let next: Publication?
    private let onOpenNext: (Publication) -> Void
    /// Where the library's own cover comes from. Task 16.10: the player drew the coverless
    /// well even for a publication the library had a cover for — an EPUB being read aloud,
    /// most often, since no audiobook cover is indexed yet (`PublicationIndexer.audiobook`).
    /// Defaulted to "no cover" so a preview or a test built without a library still compiles.
    private let coverLookup: (Publication, Int) async -> CGImage?
    @State private var showingChapters = false
    @State private var showingSpeed = false
    @State private var showingSleep = false
    /// The scrub in progress, so dragging does not fight the clock ticking underneath it.
    @State private var scrubbing: TimeInterval?
    @State private var resolvedCover: CGImage?

    public init(
        centre: PlayerCentre,
        next: Publication? = nil,
        onOpenNext: @escaping (Publication) -> Void = { _ in },
        coverLookup: @escaping (Publication, Int) async -> CGImage? = { _, _ in nil }
    ) {
        self.centre = centre
        self.next = next
        self.onOpenNext = onOpenNext
        self.coverLookup = coverLookup
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: StoryArcSpace.xl) {
                    // `centre.book` is `nil` after both a finished book and an explicit
                    // stop; `hasReachedTheEnd` is what tells them apart (see
                    // ``PlayerCentre/lastFinished``), and only the first draws an offer
                    // rather than the live transport.
                    if centre.book == nil, centre.hasReachedTheEnd {
                        PlayerFinishedOffer(next: next, onOpenNext: onOpenNext)
                    } else {
                        cover
                        names
                        position
                        transport
                        settings
                        damage
                    }
                }
                .padding(.horizontal, StoryArcSpace.gutter)
                .padding(.vertical, StoryArcSpace.xl)
                .frame(maxWidth: .infinity)
            }
            .background(theme.palette.surfaceCanvas)
        }
        // **No Close button, and the grabber in its place.** `named-failures-and-quieter-chrome`
        // §3.2: a sheet already has two ways out and the button sat exactly where the grabber
        // wants to be — top trailing, over the artwork. Drawing the grabber is what makes the
        // drag *discoverable*; it was always available and unadvertised.
        //
        // **The route a screen reader used is not the button.** VoiceOver dismisses a sheet with
        // the escape gesture, which the platform provides for every presented sheet and which
        // `.accessibilityAction(.escape)` states here so nothing depends on that being true by
        // default. `PlayerAuditTests.aSheetIsStillDismissibleWithoutACloseButton` walks it.
        //
        // Android does **not** get this change: its player is a destination rather than a sheet,
        // so it needs its back affordance and has no grabber to defer to. `tasks.md` §3.3.
        .presentationDragIndicator(.visible)
        .accessibilityAction(.escape) { dismiss() }
        .sheet(isPresented: $showingChapters) {
            ChapterListView(centre: centre)
        }
        .sheet(isPresented: $showingSpeed) {
            SpeedSheet(centre: centre).presentationDetents([.medium])
        }
        .sheet(isPresented: $showingSleep) {
            SleepTimerSheet(centre: centre).presentationDetents([.medium])
        }
    }

    // MARK: - What is playing

    /// The artwork: the library's own cover when it has one, the coverless treatment every
    /// other surface draws otherwise. See ``PlayerArtwork``, which is also what the lock
    /// screen is given.
    @ViewBuilder
    private var cover: some View {
        if let book = centre.book {
            PlayerArtwork(format: book.publication.format, cover: resolvedCover)
                .frame(maxWidth: 320)
                // Decoration. The publication is named in words directly below, and a screen
                // reader that stopped on the format first would hear the kind of thing before
                // the thing.
                .accessibilityHidden(true)
                // Keyed on the id, not the whole book: ``PlayerCentre/book`` is renamed with
                // every chapter crossed (see its own `naming(_:)`), and re-asking the library
                // for the same cover on every chapter would be the defect
                // ``LibraryModel/cover(for:maxPixelSize:)``'s own cache exists to prevent.
                .task(id: book.publication.id) {
                    resolvedCover = await coverLookup(book.publication, Int(320 * displayScale))
                }
        }
    }

    @Environment(\.displayScale) private var displayScale

    private var names: some View {
        VStack(spacing: StoryArcSpace.xs) {
            Text(centre.compact?.label.title ?? "")
                .textRole(.title2)
                .foregroundStyle(theme.palette.textPrimary)
            if let chapter = centre.compact?.label.detail {
                Text(chapter)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        // Never truncated to one word, whatever the text size. `audio-playback` asks for
        // the publication and the chapter "readable in full", which is what makes the
        // surface scroll rather than the words shrink.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Where it is

    @ViewBuilder private var position: some View {
        if centre.time.isScrubbable, let total = centre.time.total {
            VStack(spacing: StoryArcSpace.xs) {
                Slider(
                    value: Binding(
                        get: { scrubbing ?? centre.time.elapsed },
                        set: { scrubbing = $0 }
                    ),
                    in: 0...max(total, 1),
                    onEditingChanged: { editing in
                        guard !editing, let landed = scrubbing else { return }
                        centre.scrub(to: landed)
                        scrubbing = nil
                    }
                )
                .tint(theme.accent)
                // `audio-playback`: announced "as an adjustable with its position stated in
                // time, not as a percentage" — which is exactly what a `Slider` says by
                // default, and why the value is overridden here.
                .accessibilityLabel(Text("player.position", bundle: .module))
                .accessibilityValue(Text(PlayerLabels.spokenTime(scrubbing ?? centre.time.elapsed)))

                HStack {
                    Text(PlayerLabels.time(scrubbing ?? centre.time.elapsed))
                    Spacer()
                    Text(PlayerLabels.time(total))
                }
                .textRole(.caption)
                .foregroundStyle(theme.palette.textSecondary)
                .monospacedDigit()
                // The two ends of the slider are the slider's own announced value. Read
                // again as loose text they would be two more stops for no new information.
                .accessibilityHidden(true)
            }
        } else {
            // No total, so no scrubber — absent, not disabled. What is stated instead is
            // which part, which is a real position rather than an invented countdown.
            PlayerText.position(
                PlayerLabels.position(part: centre.place.partIndex, of: centre.parts.count, time: centre.time)
            )
            .textRole(.subheadline)
            .foregroundStyle(theme.palette.textSecondary)
        }
    }

    // MARK: - The transport

    private var transport: some View {
        HStack(spacing: StoryArcSpace.xl) {
            skipButton(.back)
            Button {
                centre.toggle()
            } label: {
                Image(systemName: centre.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .frame(minWidth: 64, minHeight: 64)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .accessibilityLabel(
                centre.isPlaying
                    ? Text("player.pause", bundle: .module)
                    : Text("player.play", bundle: .module)
            )
            skipButton(.forward)
        }
        // The glyphs do not grow with the text. At an accessibility size a transport whose
        // buttons had grown would be a transport pushed off the screen, which is the thing
        // `audio-playback` forbids by name.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// A skip control that states its own interval.
    ///
    /// `audio-playback`: "the interval is stated on the control itself". The glyph carries
    /// the number where the platform has one, and the label says it in words either way —
    /// including for a synthesised voice, which skips a sentence and has no number.
    private func skipButton(_ direction: SkipDirection) -> some View {
        Button {
            centre.skip(direction)
        } label: {
            Image(systemName: symbol(for: direction))
                .font(.system(size: 30))
                .frame(minWidth: 48, minHeight: 48)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.textPrimary)
        .accessibilityLabel(
            PlayerText.skip(
                PlayerLabels.skip(direction, unit: centre.skipUnit),
                direction
            )
        )
    }

    /// The platform draws `15`, `30`, `45`, `60`, `75` and `90` on its skip glyphs, and both
    /// intervals are in that set — so each button carries its own number.
    private func symbol(for direction: SkipDirection) -> String {
        guard centre.skipUnit == .time else {
            return direction == .back ? "backward.end" : "forward.end"
        }
        let side = direction == .back ? "gobackward" : "goforward"
        return "\(side).\(Int(SkipIntervals.interval(direction)))"
    }

    // MARK: - The rest of what a book player has

    private var settings: some View {
        HStack(spacing: StoryArcSpace.xl) {
            settingButton("list.bullet", Text("player.chapters", bundle: .module)) {
                showingChapters = true
            }
            settingButton(
                "speedometer",
                Text("player.speed.value \(speedText)", bundle: .module),
                label: Text("player.speed", bundle: .module),
                value: Text("player.speed.value \(speedText)", bundle: .module)
            ) { showingSpeed = true }
            // `audio-playback` asks a screen reader to hear "a name and, where it carries one,
            // its value — the speed, **the remaining sleep time**, the position". The
            // face of the control is the value; the name is stated separately, exactly as the
            // speed button beside it does.
            settingButton(
                "moon.zzz",
                sleepText,
                label: Text("player.sleep", bundle: .module),
                value: centre.sleep == nil ? nil : sleepText
            ) { showingSleep = true }
        }
    }

    /// The rate in the reader's own number format: "1,75" where they write a comma.
    private var speedText: String {
        centre.speed.rate
            .formatted(.number.precision(.fractionLength(0...2)).locale(.storyArc))
    }

    /// The remaining time, on the face of the control.
    ///
    /// `audio-playback` requires "the remaining time is shown on the player", and both kinds
    /// of timer answer with one number — a duration counts itself down, *end of chapter* is
    /// re-read from where the audio has reached — so there is no branch here on which was
    /// chosen. It moves because ``PlayerCentre/tickSleepTimer(by:)`` moves it; a static
    /// number would be the shipped defect in a different costume.
    private var sleepText: Text {
        guard let sleep = centre.sleep else { return Text("player.sleep", bundle: .module) }
        return Text("player.sleep.remaining \(PlayerLabels.time(sleep.remaining))", bundle: .module)
    }

    private func settingButton(
        _ symbol: String,
        _ caption: Text,
        label: Text? = nil,
        value: Text? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: StoryArcSpace.xs) {
                Image(systemName: symbol).font(.system(size: 20))
                caption.textRole(.caption)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.textPrimary)
        // `audio-playback`: a control is announced "with a name and, where it carries one,
        // its value". A speed button reading only "1.5×" is a value with no name.
        .accessibilityLabel(label ?? caption)
        .accessibilityValue(value ?? Text(verbatim: ""))
    }

    /// What could not be played, in the player's own controls.
    ///
    /// `publication-formats` requires the count to be stated "rather than interrupting
    /// playback", so it is a line on this surface and never an alert.
    private var damage: some View {
        PlayerText.damage(unreadableParts: centre.unreadablePartCount)
            .textRole(.caption)
            .foregroundStyle(theme.palette.textSecondary)
            .multilineTextAlignment(.center)
    }
}
