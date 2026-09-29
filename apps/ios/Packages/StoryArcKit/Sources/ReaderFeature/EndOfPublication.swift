public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// What the reader shows after the last page.
///
/// `comic-reader`: "an end screen offers the next publication in the series or
/// reading list, marks this one finished". Marking is already done — the last page
/// records `isFinished` as it is turned to, because a reader who closes the app on
/// the last page has still finished it.
///
/// Deleting the download is offered by the same scenario, and is here now (D7): an
/// action to remove it when the reader closes, or — when that is already due — a
/// sentence saying so and an action to keep this one instead.
///
/// Split out of `ReaderPage.swift`, which had reached the 400-line cap this project
/// enforces once D7 joined it.
struct EndOfPublication: View {
    @Environment(\.theme) private var theme

    let title: String
    /// What the cover brings, or `nil` for a cover with no colour of its own.
    ///
    /// `native-experience` puts a cover-derived accent and background tint "on a
    /// publication detail screen or the reader". This screen is where the reader can
    /// honour that: everywhere else in it the artwork is *on* screen, and the
    /// non-negotiable is that chrome over a page never tints. Here the page is behind a
    /// near-opaque sheet, so the colour has somewhere to go.
    let colours: CoverColours?
    let next: Publication?
    let onOpenNext: (Publication) -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    /// `nil` for a publication that was never a download. See ``DownloadCleanupOffer``.
    var downloadCleanup: DownloadCleanupOffer?

    /// The reader's tap on this screen about the download — true for "Remove download",
    /// false for "Keep" — so the row answers the tap at once.
    @State private var cleanupChoice: Bool?

    /// The cover's accent, or the brand's. Never the raw extracted colour — what
    /// ``CoverColours`` carries has already been adjusted to clear the floor.
    private var accent: Color {
        colours.flatMap { Color(readerHex: $0.accent) } ?? theme.palette.accent
    }

    /// What is written on that accent, chosen for it rather than assumed to be white.
    private var onAccent: Color {
        colours.flatMap { Color(readerHex: $0.onAccent) } ?? .white
    }

    var body: some View {
        ZStack {
            // The wash, fading to black. Still near-opaque: the last page stays faintly
            // visible behind it, which is what says this screen is over the book rather
            // than after it.
            LinearGradient(
                colors: [colours.flatMap { Color(readerHex: $0.wash) } ?? .black, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.92)
            .ignoresSafeArea()

            VStack(spacing: StoryArcSpace.lg) {
                VStack(spacing: StoryArcSpace.xs) {
                    Text("reader.end.finished", bundle: .module)
                        .textRole(.title3)
                        .foregroundStyle(.white)
                    Text(title)
                        .textRole(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                if let next {
                    Button {
                        onOpenNext(next)
                    } label: {
                        Text("reader.end.next \(next.displayTitle)", bundle: .module)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, StoryArcSpace.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .foregroundStyle(onAccent)
                }

                downloadCleanupRow

                HStack(spacing: StoryArcSpace.md) {
                    Button(action: onBack) {
                        Text("reader.end.back", bundle: .module)
                    }
                    Button(action: onClose) {
                        Text("reader.end.library", bundle: .module)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .frame(maxWidth: StoryArcSpace.huge * 6)
        }
        .transition(.opacity)
    }

    /// D7: an action to remove the download, or — with the sweep already doing that —
    /// a sentence saying so and an action to keep this one instead.
    @ViewBuilder
    private var downloadCleanupRow: some View {
        if let offer = downloadCleanup {
            switch DownloadCleanupPresentation.resolved(for: offer, choice: cleanupChoice) {
            case .none:
                EmptyView()
            case .offerRemoval:
                Button(role: .destructive) {
                    offer.onRemove()
                    cleanupChoice = true
                } label: {
                    Text("reader.end.removeDownload", bundle: .module)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            case .stateAndOfferKeep:
                VStack(spacing: StoryArcSpace.xs) {
                    Text("reader.end.downloadWillBeRemoved", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Button {
                        offer.onKeep()
                        cleanupChoice = false
                    } label: {
                        Text("reader.end.keepDownload", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }
    }
}
