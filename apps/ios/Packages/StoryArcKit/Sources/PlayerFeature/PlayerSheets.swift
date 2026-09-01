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
                row(
                    Text("player.sleep.endOfChapter", bundle: .module),
                    isChosen: centre.sleep?.timer == .endOfChapter
                ) {
                    centre.setSleepTimer(.endOfChapter)
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
