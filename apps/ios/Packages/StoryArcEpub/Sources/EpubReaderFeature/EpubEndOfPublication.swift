public import SwiftUI

internal import DesignSystem
internal import ReadiumShared
public import StoryArcCore

/// Offered over the last page of a reflowable book, the way the comic reader's own end
/// screen is offered over its last page.
///
/// `collections-and-reading-lists` task 7.2: "at the end of a reflowable EPUB... offer
/// `library.next(after:)` the way the paged reader's end screen does". A separate type
/// rather than a reuse of `ReaderFeature`'s `EndOfPublication`: that type lives in
/// `StoryArcKit`, which this package does not depend on, and the EPUB reader's chrome is
/// its own module for exactly that reason (ADR-0001).
///
/// D21: this surface takes the cover's accent, as the comic reader's end screen does. The
/// chrome over the page stays untinted, which is the glass rule.
struct EpubEndOfPublication: View {
    @Environment(\.theme) private var theme

    let next: StoryArcCore.Publication
    /// The cover's colours, or `nil` for a cover with none, which keeps the brand accent.
    var colours: CoverColours?
    let onOpenNext: (StoryArcCore.Publication) -> Void

    /// The cover's adjusted accent, or the brand's. Never the raw extracted colour.
    private var accent: Color {
        colours.map { Color(hex: $0.accent) } ?? theme.palette.accent
    }

    /// What is written on that accent, chosen for it rather than assumed to be white.
    private var onAccent: Color {
        colours.map { Color(hex: $0.onAccent) } ?? .white
    }

    var body: some View {
        VStack(spacing: StoryArcSpace.md) {
            Text("epub.end.finished", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(.white.opacity(0.85))

            Button {
                onOpenNext(next)
            } label: {
                Text("epub.end.next \(next.displayTitle)", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StoryArcSpace.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .foregroundStyle(onAccent)
        }
        .padding(StoryArcSpace.gutter)
        .frame(maxWidth: StoryArcSpace.huge * 6)
        .background(
            RoundedRectangle(cornerRadius: StoryArcSpace.md)
                .fill(.black.opacity(0.78))
        )
        .padding(.bottom, StoryArcSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }
}

extension EpubReaderModel {
    /// Reads the cover's colours once the book is open, as the comic reader does from its
    /// cover page. A book with no cover, or a cover with no colour, leaves `nil`.
    func deriveCoverColours() async {
        guard coverColours == nil else { return }
        coverColours = await Self.coverColours(of: opened)
    }

    /// `nonisolated`, as `recordedLocator()` is: Readium's cover lookup is handed the
    /// publication through the `nonisolated(unsafe)` property rather than a main-actor copy.
    nonisolated static func coverColours(of opened: ReadiumShared.Publication?) async -> CoverColours? {
        guard let opened, let image = try? await opened.cover().get()?.cgImage else { return nil }
        return coverColours(of: image)
    }

    /// The colours one cover gives its end of book: `CoverAccent`, which both readers share.
    nonisolated static func coverColours(of image: CGImage) -> CoverColours? {
        CoverAccent.pixels(of: image).flatMap(CoverAccent.derived(from:))
    }

    /// Whether what is on screen reaches the end — this offer's own cue, read through the
    /// same rule ``record(_:)`` uses to mark a position finished.
    var isAtEnd: Bool {
        Self.isAtEnd(total: progression, viewportUpperBound: navigator?.viewport?.progression.upperBound)
    }
}
