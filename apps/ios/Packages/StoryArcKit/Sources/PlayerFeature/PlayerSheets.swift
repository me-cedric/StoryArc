public import SwiftUI

internal import DesignSystem
public import Playback
internal import StoryArcCore

/// Every chapter, with its length, its mark, and how much of the current one is left.
///
/// `audio-playback`: "every chapter is listed with its duration, and choosing one moves there
/// … a chapter already finished is marked as finished, a chapter not yet reached carries no
/// mark, and the chapter in progress is marked as the one in progress … the chapter in progress
/// also states how much of itself is left … a publication with no chapter markers lists its
/// parts in playing order instead, rather than showing an empty list".
///
/// **The marks are ``ChapterProgress``'s rule, not this file's.** The publication page's
/// ``DetailChapterList`` reads the same rule, because the spec asks "every surface that lists
/// chapters" for the same three marks — and because measured on 2026-09-08 these two lists
/// disagreed, this one marking only the chapter being played.
///
/// **There is no branch for the second half.** The parts a source reports are the list, and
/// a source with no chapter markers reports one part rather than none — the rule lives in
/// `AudiobookReader`, where the container is read, so nothing here has to know that an
/// unchaptered book is a special case. What is left is naming an unnamed part, which is
/// ``PlayerLabels/chapter(_:)``.
public struct ChapterListView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    /// Read for the reason `SourceDetail` reads it: four items on one row do not fit at the
    /// accessibility sizes. See ``ChapterListView/row(_:mark:)``.
    @Environment(\.dynamicTypeSize) private var typeSize

    private let centre: PlayerCentre

    public init(centre: PlayerCentre) {
        self.centre = centre
    }

    public var body: some View {
        NavigationStack {
            List(centre.parts) { part in
                let mark = ChapterProgress.mark(
                    of: part.index,
                    reached: centre.place.partIndex,
                    isFinished: centre.hasReachedTheEnd
                )
                Button {
                    centre.play(part: part.index)
                    dismiss()
                } label: {
                    row(part, mark: mark)
                }
                .buttonStyle(.plain)
                // The value and the traits sit on the *button*, as the speed sheet's and the
                // sleep sheet's below do. Measured on 2026-09-09: inside the button's label
                // neither reached the element a screen reader stops on, so a row read out as
                // "Chapter 3, 8 minutes 32 seconds left, 12:34, button" and stated no mark.
                //
                // The length is the row's value, spoken in words: a screen reader handed
                // `12:34` says "twelve colon thirty four". The printed copy is silenced where
                // it is drawn, so the row states its length once. The publication page's list
                // states it the same way.
                .accessibilityValue(Text(part.duration.map(PlaybackClock.spokenTime) ?? ""))
                // **No `isSelected`.** The glyph carries the mark as a word — see ``mark(_:)``
                // — and the trait says the same thing again: measured on 2026-09-09, the row
                // in progress read out "in progress" and then "selected". The finished mark
                // needs a word regardless, there being no trait for it, so one carrier for all
                // three marks is the only shape where no row states its mark twice.
                .accessibilityAddTraits(.isButton)
            }
            .navigationTitle(Text("player.chapters", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("player.close", bundle: .module) }
                }
            }
        }
    }

    /// One row: the mark and the chapter, then what is left of it and how long it runs.
    ///
    /// **Stacked at the accessibility sizes**, the shape `SourceDetail`'s fields take for the
    /// reason photographed on 2026-09-05: a value squeezed into a third of the width wrapped
    /// mid-word, and this row carries four items rather than that one's two.
    private func row(_ part: PlaybackPart, mark: ChapterMark) -> some View {
        // `centre.place`, never `centre.recorded`: the place the source reports, rather than a
        // position a surface published earlier. The centre reports four times a second and
        // `place` is observed, so this number counts down while the sheet is open.
        let left = ChapterProgress.remainder(
            ofChapterLasting: part.duration,
            mark: mark,
            at: centre.place.offset
        )
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    heading(part, mark: mark)
                    facts(part, left: left)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: StoryArcSpace.md) {
                    heading(part, mark: mark)
                    Spacer(minLength: StoryArcSpace.sm)
                    facts(part, left: left)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// The mark and the chapter's name, which stay beside each other at every size.
    private func heading(_ part: PlaybackPart, mark: ChapterMark) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            self.mark(mark)
            PlayerText.chapter(PlayerLabels.chapter(part))
                .foregroundStyle(theme.palette.textPrimary)
        }
    }

    /// What is left of the chapter, and how long the chapter runs.
    private func facts(_ part: PlaybackPart, left: TimeInterval?) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            if let left {
                remainder(left)
            }
            if let length = PlayerLabels.length(of: part) {
                Text(length)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
                    .monospacedDigit()
                    // Silent, because the row already states its length as its value in words.
                    // Measured on 2026-09-09: the printed copy joined the combined label, so a
                    // row read out "12:34" and then "12 minutes 34 seconds" — and the clock
                    // face as "twelve colon thirty four", which ``PlaybackClock/spokenTime``
                    // exists to prevent. Android silences its printed copy the same way.
                    .accessibilityHidden(true)
            }
        }
    }

    /// The mark, and it is a glyph rather than a colour alone: a listener who cannot separate
    /// the accent from the text colour still has to be able to see where they are.
    ///
    /// The glyph is ``ChapterMark/glyph``'s, so this file cannot draw one the rule did not
    /// choose. The publication page draws the same three, because `audio-playback` asks "every
    /// surface that lists chapters" for all three marks.
    ///
    /// **Two of the three carry a word.** Measured on 2026-09-09: the mark in progress had only
    /// the row's ``AccessibilityTraits/isSelected`` to carry it, so a screen reader stated no
    /// mark on that row while every finished row above it said "Finished". A chapter not yet
    /// reached "carries no mark", so its glyph carries no word either.
    @ViewBuilder
    private func mark(_ mark: ChapterMark) -> some View {
        let glyph = Image(systemName: mark.glyph).foregroundStyle(tint(of: mark))
        switch mark {
        case .inProgress: glyph.accessibilityLabel(Text("player.chapter.inProgress", bundle: .module))
        case .finished: glyph.accessibilityLabel(Text("player.chapter.finished", bundle: .module))
        case .unplayed: glyph.accessibilityHidden(true)
        }
    }

    private func tint(of mark: ChapterMark) -> Color {
        switch mark {
        case .inProgress: theme.accent
        case .finished: theme.palette.textSecondary
        case .unplayed: theme.palette.borderSubtle
        }
    }

    /// How much of the chapter in progress is left.
    ///
    /// `design.md`, amended 2026-09-08: the remainder is stated as time rather than drawn as a
    /// bar, because "eight minutes left" answers the question a listener is asking and reads
    /// out with no extra work. The clock face beside the row's own length, so one row never
    /// mixes two notations; the label is the same time in words, and it joins the row's
    /// combined label rather than becoming a second stop for a screen reader.
    private func remainder(_ seconds: TimeInterval) -> some View {
        Text("player.chapter.remaining \(PlaybackClock.time(seconds))", bundle: .module)
            .textRole(.caption)
            .foregroundStyle(theme.accent)
            .monospacedDigit()
            .accessibilityLabel(
                Text("player.chapter.remaining \(PlaybackClock.spokenTime(seconds))", bundle: .module)
            )
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

    /// The rate in the reader's own number format: "1,75" where they write a comma.
    private func number(_ speed: PlaybackSpeed) -> String {
        speed.rate.formatted(.number.precision(.fractionLength(0...2)).locale(.storyArc))
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
