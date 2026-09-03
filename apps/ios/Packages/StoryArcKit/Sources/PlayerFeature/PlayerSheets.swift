public import SwiftUI

internal import DesignSystem
public import Playback

/// Every chapter, with its length, and the one being played marked.
///
/// `audio-playback`: "every chapter is listed with its duration and the current one marked,
/// and choosing one moves there … a publication with no chapter markers lists its parts in
/// playing order instead, rather than showing an empty list".
///
/// **There is no branch for the second half.** The parts a source reports are the list, and
/// a source with no chapter markers reports one part rather than none — the rule lives in
/// `AudiobookReader`, where the container is read, so nothing here has to know that an
/// unchaptered book is a special case. What is left is naming an unnamed part, which is
/// ``PlayerLabels/chapter(_:)``.
public struct ChapterListView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let centre: PlayerCentre

    public init(centre: PlayerCentre) {
        self.centre = centre
    }

    public var body: some View {
        NavigationStack {
            List(centre.parts) { part in
                Button {
                    centre.play(part: part.index)
                    dismiss()
                } label: {
                    row(part)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(Text("player.chapters", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("player.close", bundle: .module) }
                }
            }
        }
    }

    private func row(_ part: PlaybackPart) -> some View {
        let isPlaying = part.index == centre.place.partIndex
        return HStack(spacing: StoryArcSpace.md) {
            // The mark, and it is a glyph rather than a colour alone: a listener who cannot
            // separate the accent from the text colour still has to be able to see which
            // chapter is playing.
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "circle")
                .foregroundStyle(isPlaying ? theme.accent : theme.palette.borderSubtle)
                .accessibilityHidden(true)
            PlayerText.chapter(PlayerLabels.chapter(part))
                .foregroundStyle(theme.palette.textPrimary)
            Spacer(minLength: StoryArcSpace.sm)
            if let length = PlayerLabels.length(of: part) {
                Text(length)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        // Selected is a trait rather than a word, so a screen reader says it in the
        // listener's own language without this file owning a string for it.
        .accessibilityAddTraits(isPlaying ? [.isButton, .isSelected] : .isButton)
    }
}

/// How fast the words come.
///
/// `audio-playback`: the value "is stated as a number", and at least half to triple speed is
/// offered. The stops are ``PlaybackSpeed/stops``; the range they are drawn from is the
/// **product decision** `design.md` records, and no guideline is cited for it.
public struct SpeedSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let centre: PlayerCentre

    public init(centre: PlayerCentre) {
        self.centre = centre
    }

    public var body: some View {
        NavigationStack {
            List(PlaybackSpeed.stops, id: \.rate) { speed in
                Button {
                    centre.setSpeed(speed)
                    dismiss()
                } label: {
                    HStack {
                        Text("player.speed.value \(number(speed))", bundle: .module)
                            .foregroundStyle(theme.palette.textPrimary)
                        Spacer()
                        if speed == centre.speed {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(speed == centre.speed ? [.isButton, .isSelected] : .isButton)
            }
            .navigationTitle(Text("player.speed", bundle: .module))
        }
    }

    private func number(_ speed: PlaybackSpeed) -> String {
        speed.rate.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// When to stop.
///
/// `audio-playback`: "a duration or *end of chapter* may be chosen". The end-of-chapter
/// option is the **product decision** `design.md` records — a music player has no reason to
/// offer it, a book player does, and it is the one a listener falling asleep actually wants.
///
/// **End of chapter is absent rather than inert where nothing knows how long the chapter
/// is.** A session being read aloud has no true duration, so there is no end to stop at, and
/// "every control the player offers works, or is absent — none is present and refusing"
/// applies to the one row that cannot always be honoured. The row asks
/// ``PlayerCentre/canSleepAtEndOfChapter``; Android's chip asks the same question and is not
/// drawn either.
public struct SleepTimerSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let centre: PlayerCentre

    public init(centre: PlayerCentre) {
        self.centre = centre
    }

    public var body: some View {
        NavigationStack {
            List {
                row(Text("player.sleep.off", bundle: .module), isChosen: centre.sleep == nil) {
                    centre.setSleepTimer(nil)
                }
                if centre.canSleepAtEndOfChapter {
                    row(
                        Text("player.sleep.endOfChapter", bundle: .module),
                        isChosen: centre.sleep?.timer == .endOfChapter
                    ) {
                        centre.setSleepTimer(.endOfChapter)
                    }
                }
                ForEach(SleepTimer.durations, id: \.self) { seconds in
                    row(
                        Text(PlayerLabels.time(seconds)),
                        isChosen: centre.sleep?.timer == .after(seconds)
                    ) {
                        centre.setSleepTimer(.after(seconds))
                    }
                }
            }
            .navigationTitle(Text("player.sleep", bundle: .module))
        }
    }

    private func row(_ label: Text, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                label.foregroundStyle(theme.palette.textPrimary)
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// How far one press of a skip control moves.
///
/// **`audio-playback` asks for an interval "the listener can configure", and until this sheet
/// there was nothing to configure it with.** `PlayerCentre.skipIntervals` was read by the
/// player, the timeline and the lock screen and written by nobody, so the requirement's second
/// clause was unmet with nothing failing — the kind of gap a task list ticks and a reader finds.
///
/// Two pickers rather than one, because the two directions are genuinely different distances:
/// the reason to skip back is "I missed that sentence" and the reason to skip forward is "I know
/// this part". They are stored together because to a listener they are one setting.
public struct SkipIntervalsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let centre: PlayerCentre

    public init(centre: PlayerCentre) {
        self.centre = centre
    }

    public var body: some View {
        NavigationStack {
            List {
                section(.back, title: Text("player.skip.back", bundle: .module))
                section(.forward, title: Text("player.skip.forward", bundle: .module))
            }
            .navigationTitle(Text("player.skip", bundle: .module))
        }
    }

    @ViewBuilder
    private func section(_ direction: SkipDirection, title: Text) -> some View {
        Section {
            ForEach(SkipIntervals.offered, id: \.self) { seconds in
                row(direction, seconds: seconds)
            }
        } header: {
            title
        }
    }

    private func row(_ direction: SkipDirection, seconds: TimeInterval) -> some View {
        let isChosen = centre.skipIntervals.interval(direction) == seconds
        return Button {
            centre.setSkipIntervals(changing(direction, to: seconds))
        } label: {
            HStack {
                Text("player.skip.seconds \(Int(seconds))", bundle: .module)
                    .foregroundStyle(theme.palette.textPrimary)
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// The pair with one direction changed. The sheet stays open: a listener setting both
    /// would otherwise have to reopen it, and this is the one sheet in the player that holds
    /// two decisions rather than one.
    private func changing(_ direction: SkipDirection, to seconds: TimeInterval) -> SkipIntervals {
        var intervals = centre.skipIntervals
        switch direction {
        case .back: intervals.back = seconds
        case .forward: intervals.forward = seconds
        }
        return intervals
    }
}
