public import SwiftUI

internal import DesignSystem
public import Playback

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
    @State private var showingChapters = false
    @State private var showingSpeed = false
    @State private var showingSleep = false
    /// The scrub in progress, so dragging does not fight the clock ticking underneath it.
    @State private var scrubbing: TimeInterval?

    public init(centre: PlayerCentre) {
        self.centre = centre
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: StoryArcSpace.xl) {
                    cover
                    names
                    position
                    transport
                    settings
                    damage
                }
                .padding(.horizontal, StoryArcSpace.gutter)
                .padding(.vertical, StoryArcSpace.xl)
                .frame(maxWidth: .infinity)
            }
            .background(theme.palette.surfaceCanvas)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("player.close", bundle: .module) }
                }
            }
        }
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

    /// The artwork, or the space it would occupy.
    ///
    /// No cover is read out of an audiobook yet — see `PublicationIndexer.audiobook` — so
    /// this is the same placeholder the library draws for a publication with no art rather
    /// than a broken image or a gap.
    private var cover: some View {
        RoundedRectangle(cornerRadius: StoryArcRadius.lg, style: .continuous)
            .fill(theme.palette.surfaceRaised)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 320)
            .overlay {
                Image(systemName: "headphones")
                    .font(.system(size: 64))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            // Decoration. The publication is named in words directly below, and a screen
            // reader that stopped on a placeholder first would be reading furniture.
            .accessibilityHidden(true)
    }

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
                PlayerLabels.skip(direction, unit: centre.skipUnit, intervals: centre.skipIntervals),
                direction
            )
        )
    }

    /// The platform draws `15`, `30`, `45`, `60`, `75` and `90` on its skip glyphs, and
    /// nothing else — so an interval it has no glyph for gets the plain arrow, with the
    /// number still stated in the label.
    private func symbol(for direction: SkipDirection) -> String {
        guard centre.skipUnit == .time else {
            return direction == .back ? "backward.end" : "forward.end"
        }
        let seconds = Int(centre.skipIntervals.interval(direction))
        let side = direction == .back ? "gobackward" : "goforward"
        return [15, 30, 45, 60, 75, 90].contains(seconds) ? "\(side).\(seconds)" : side
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
            // its value — the speed, the skip interval, **the remaining sleep time**". The
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

    private var speedText: String {
        centre.speed.rate
            .formatted(.number.precision(.fractionLength(0...2)))
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
