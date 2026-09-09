internal import SwiftUI

internal import DesignSystem
internal import Playback

/// An audiobook's chapters, on the page rather than inside the player.
///
/// `audio-playback`: "a listener SHALL be able to see an audiobook's chapters without
/// starting it, and SHALL be able to start at any one of them". The player's own
/// ``ChapterListView`` draws the same rows from the same parts; what differs is that this one
/// is reached without playing anything, and that it sits inside the page's own scroll view
/// rather than in a `List` of its own.
///
/// Nothing at all for a comic, for a single-part audiobook, and for a publication whose bytes
/// the device does not hold — ``DetailChapters/of(_:parts:progress:)`` decides which, and this
/// draws whatever it was handed.
struct DetailChapterList: View {
    @Environment(\.theme) private var theme
    /// Read for the reason `SourceDetail` reads it: four items on one row do not fit at the
    /// accessibility sizes. See ``DetailChapterList/row(_:)``.
    @Environment(\.dynamicTypeSize) private var typeSize

    let chapters: [DetailChapter]

    /// What to do with the chapter a listener chose, or `nil` where nothing can start
    /// playback from this page yet. The rows are still drawn without it: seeing the chapters
    /// without starting the book is the first half of what this list is for, and a button
    /// that is present and refusing is what `audio-playback` forbids.
    let onChoose: ((Int) -> Void)?

    var body: some View {
        if !chapters.isEmpty {
            VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                Text("detail.chapters", bundle: .module)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)

                ForEach(chapters) { chapter in
                    if let onChoose {
                        let button = Button { onChoose(chapter.index) } label: { row(chapter) }
                        stated(chapter, button.buttonStyle(.plain), isChoosable: true)
                    } else {
                        stated(chapter, row(chapter), isChoosable: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One row: the mark and the chapter, then what is left of it and how long it runs.
    ///
    /// **Stacked at the accessibility sizes**, the shape `SourceDetail`'s fields take for the
    /// reason photographed on 2026-09-05: a value squeezed into a third of the width wrapped
    /// mid-word, and this row carries four items rather than that one's two.
    private func row(_ chapter: DetailChapter) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    heading(chapter)
                    facts(chapter)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: StoryArcSpace.md) {
                    heading(chapter)
                    Spacer(minLength: StoryArcSpace.sm)
                    facts(chapter)
                }
            }
        }
        .padding(.vertical, StoryArcSpace.xs)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// The mark and the chapter's name, which stay beside each other at every size.
    private func heading(_ chapter: DetailChapter) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            mark(chapter.mark)
            name(chapter.name)
                .textRole(.body)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What is left of the chapter, and how long the chapter runs.
    private func facts(_ chapter: DetailChapter) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            if let remaining = chapter.remaining {
                remainder(remaining)
            }
            if let duration = chapter.duration {
                Text(PlaybackClock.time(duration))
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

    /// The row's spoken facts, on the element a screen reader actually stops on.
    ///
    /// **Outside the button rather than inside its label.** Measured on 2026-09-09: a trait
    /// added inside a `Button`'s label never reaches the button's own element, so the mark in
    /// progress went unspoken while every finished row above it said "Finished". The speed
    /// sheet and the sleep sheet in `PlayerSheets.swift` have always put theirs on the button.
    ///
    /// The length is the row's *value*, spoken in words: a screen reader handed `12:34` says
    /// "twelve colon thirty four". The printed copy is silenced where it is drawn.
    ///
    /// **`isChoosable` is the caller's own `onChoose`**, and it decides the button trait. The
    /// list draws plain rows for a publication the page cannot start — a Kavita series the
    /// device holds nothing of — and a row that announces itself as a button there offers a
    /// screen reader an action that does nothing.
    ///
    /// **And no `isSelected`.** The glyph carries the mark as a word on all three marks, so
    /// the trait would state it twice; measured on 2026-09-09.
    private func stated(
        _ chapter: DetailChapter,
        _ content: some View,
        isChoosable: Bool
    ) -> some View {
        content
            .accessibilityValue(Text(chapter.duration.map(PlaybackClock.spokenTime) ?? ""))
            .accessibilityAddTraits(isChoosable ? .isButton : [])
    }

    /// How much of the chapter in progress is left.
    ///
    /// `design.md`, amended 2026-09-08: the remainder is stated as time rather than drawn as a
    /// bar, because "eight minutes left" answers the question a listener is asking and reads
    /// out with no extra work. The clock face beside the row's own length, so one row never
    /// mixes two notations; the label is the same time in words, and it joins the row's
    /// combined label rather than becoming a second stop for a screen reader.
    private func remainder(_ seconds: TimeInterval) -> some View {
        Text("detail.chapter.remaining \(PlaybackClock.time(seconds))", bundle: .module)
            .textRole(.caption)
            .foregroundStyle(theme.accent)
            .monospacedDigit()
            .accessibilityLabel(
                Text("detail.chapter.remaining \(PlaybackClock.spokenTime(seconds))", bundle: .module)
            )
    }

    /// The mark, and it is a glyph rather than a colour alone: a listener who cannot separate
    /// the accent from the text colour still has to be able to see where they are.
    ///
    /// The glyph is ``ChapterMark/glyph``'s, so this file cannot draw one the rule did not
    /// choose. The player's own list draws the same three.
    ///
    /// **Two of the three carry a word.** Measured on 2026-09-09: the mark in progress had only
    /// a trait to carry it, and the trait sat inside a button's label where it reached nothing,
    /// so the row stated no mark. A chapter not yet reached "carries no mark", so its glyph
    /// carries no word either.
    @ViewBuilder
    private func mark(_ mark: ChapterMark) -> some View {
        let glyph = Image(systemName: mark.glyph).foregroundStyle(tint(of: mark))
        switch mark {
        case .inProgress: glyph.accessibilityLabel(Text("detail.chapter.inProgress", bundle: .module))
        case .finished: glyph.accessibilityLabel(Text("detail.chapter.finished", bundle: .module))
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

    private func name(_ name: ChapterName) -> Text {
        switch name {
        case let .given(title): Text(title)
        case let .numbered(number): Text("detail.chapter.number \(number)", bundle: .module)
        }
    }
}

/// How long the book runs, for the audiobook that has no list to say it in.
///
/// `audio-playback`: an audiobook with one part "states the book's duration and offers no
/// list" — and "nothing is reported as missing, by the same rule that opens an unchaptered
/// audiobook without complaint". So a book whose length nothing knows draws nothing here,
/// rather than a row saying `0:00`.
struct DetailBookLength: View {
    @Environment(\.theme) private var theme

    let seconds: TimeInterval?

    var body: some View {
        if let seconds {
            Text("detail.duration \(PlaybackClock.time(seconds))", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .accessibilityLabel(Text("detail.duration \(PlaybackClock.spokenTime(seconds))", bundle: .module))
        }
    }
}
