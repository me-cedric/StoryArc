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
                        Button { onChoose(chapter.index) } label: { row(chapter) }
                            .buttonStyle(.plain)
                    } else {
                        row(chapter)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ chapter: DetailChapter) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            mark(chapter.mark)
            name(chapter.name)
                .textRole(.body)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: StoryArcSpace.sm)
            if let duration = chapter.duration {
                Text(PlaybackClock.time(duration))
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, StoryArcSpace.xs)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        // The length is the row's *value*, spoken in words: a screen reader handed `12:34`
        // says "twelve colon thirty four".
        .accessibilityValue(Text(chapter.duration.map(PlaybackClock.spokenTime) ?? ""))
        // Selected is a trait rather than a word, so a screen reader says it in the
        // listener's own language without this file owning a string for it.
        .accessibilityAddTraits(chapter.mark == .inProgress ? [.isButton, .isSelected] : .isButton)
    }

    /// The mark, and it is a glyph rather than a colour alone: a listener who cannot separate
    /// the accent from the text colour still has to be able to see where they are.
    ///
    /// *Finished* has no trait of its own, so the glyph carries the word. *In progress* has
    /// one — ``AccessibilityTraits/isSelected``, added to the row — so its glyph is silent
    /// rather than announced twice.
    @ViewBuilder
    private func mark(_ mark: ChapterMark) -> some View {
        switch mark {
        case .inProgress:
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.palette.textSecondary)
                .accessibilityLabel(Text("detail.chapter.finished", bundle: .module))
        case .unplayed:
            Image(systemName: "circle")
                .foregroundStyle(theme.palette.borderSubtle)
                .accessibilityHidden(true)
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
