public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// Offered over the last page of a reflowable book, the way the comic reader's own end
/// screen is offered over its last page.
///
/// `collections-and-reading-lists` task 7.2: "at the end of a reflowable EPUB... offer
/// `library.next(after:)` the way the paged reader's end screen does". A separate type
/// rather than a reuse of `ReaderFeature`'s `EndOfPublication`: that type lives in
/// `StoryArcKit`, which this package does not depend on, and the EPUB reader's chrome is
/// its own module for exactly that reason (ADR-0001).
struct EpubEndOfPublication: View {
    @Environment(\.theme) private var theme

    let next: Publication
    let onOpenNext: (Publication) -> Void

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
            .tint(theme.palette.accent)
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
    /// Whether what is on screen reaches the end — this offer's own cue, read through the
    /// same rule ``record(_:)`` uses to mark a position finished.
    var isAtEnd: Bool {
        Self.isAtEnd(total: progression, viewportUpperBound: navigator?.viewport?.progression.upperBound)
    }
}
