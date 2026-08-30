internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// *Keep reading*, as the one hero moment on the surface.
///
/// A horizontally paged run of large cards rather than another row of thumbnails. The
/// reasoning is the owner's constraint: the artwork **is** the interface, so the things a
/// reader is in the middle of are shown at the size the art deserves, and everything else
/// on Home is a shelf beneath them. One hero, not two — a second would make neither of
/// them one.
///
/// The card breaks `design.md`'s cover-cell rule that a title never sits over artwork, and
/// deliberately: that rule is about a *grid*, where a title over the art would be a caption
/// competing with sixty others. This is the editorial card the direction asks for — a small
/// uppercase kicker, the title, and what is left to read — over a gradient the art fades
/// into. The scrim is a gradient rather than a glass chip on purpose: the HIG says
/// non-interactive status text does not take the material, and glass belongs to the
/// navigation layer, not to a card in the content.
struct HomeHero: View {
    let publications: [Publication]
    let model: LibraryModel
    let onOpen: (Publication) -> Void

    /// How much of the width one card takes, leaving the next one peeking by the rest.
    ///
    /// The peek is the affordance: a card that filled the width edge to edge would look
    /// like the whole section, and a reader would have no reason to push it.
    private static let cardShare: CGFloat = 0.86

    /// The widest a card grows. A phone never reaches it; a 13-inch iPad would otherwise
    /// hand one publication a frame the size of a page.
    private static let widestCard: CGFloat = 420

    /// Cover proportions, opened out a little. Comic trim is 2:3; the card is 4:5, which
    /// is enough room for the caption without either cropping the art or leaving a band of
    /// wash under every cover.
    private static let cardAspect: CGFloat = 1.25

    @State private var available: CGFloat = 0

    private var cardWidth: CGFloat {
        min(max(available * Self.cardShare, 0), Self.widestCard)
    }

    var body: some View {
        Group {
            // `home-screen`: with fewer in progress than a carousel needs to make sense,
            // Keep reading "presents as a single large card rather than as a carousel of
            // one". One is that case. Two is not — collapsing there would hide a
            // publication the reader is in the middle of, which is the thing this section
            // exists to never do.
            if publications.count == 1, let only = publications.first {
                card(only)
                    .padding(.horizontal, StoryArcSpace.gutter)
            } else {
                carousel
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: StoryArcSpace.md) {
                ForEach(publications) { publication in
                    card(publication)
                        // Depth as cards pass: the one in the middle is the one being
                        // offered, and the ones beside it say so by standing back.
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.7)
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        // Cards come to rest on their own edges rather than mid-cover.
        .scrollTargetBehavior(.viewAligned)
        // Margins on the scroll *content*, so the first card starts at the gutter and the
        // run still scrolls edge to edge underneath it.
        .contentMargins(.horizontal, StoryArcSpace.gutter, for: .scrollContent)
    }

    private func card(_ publication: Publication) -> some View {
        HomeHeroCard(
            publication: publication,
            model: model,
            width: cardWidth,
            height: cardWidth * Self.cardAspect,
            onOpen: onOpen
        )
    }
}

/// One publication the reader is part-way through.
private struct HomeHeroCard: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    let width: CGFloat
    let height: CGFloat
    let onOpen: (Publication) -> Void

    /// Whether the reader could open it right now.
    ///
    /// `home-screen` keeps an unreachable publication on the shelf, dimmed, "because a row
    /// that shrinks with the Wi-Fi reads as lost reading".
    private var isReadable: Bool { model.isReadableNow(publication) }

    var body: some View {
        HomeArtwork(publication: publication, model: model, width: width, washesBehind: true)
            .frame(width: width, height: height)
            .overlay { shade }
            .overlay(alignment: .bottomLeading) { caption }
            .clipShape(.rect(cornerRadius: StoryArcRadius.lg))
            .overlay {
                // A hairline rather than a shadow: a pale cover on a pale surface needs an
                // edge, and a shadow under each card reads as noise once they are moving.
                RoundedRectangle(cornerRadius: StoryArcRadius.lg)
                    .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
            }
            .opacity(isReadable ? 1 : 0.55)
            .contentShape(.rect)
            .onTapGesture { if isReadable { onOpen(publication) } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(isReadable ? .isButton : [])
    }

    /// The gradient the art fades into, so the words over it are legible on any cover.
    ///
    /// Starts well down the card: a scrim that began at the top would be a filter over the
    /// artwork, which is the one thing this app does not do to a cover.
    private var shade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.4),
                .init(color: theme.palette.scrim.opacity(0.55), location: 0.72),
                .init(color: theme.palette.scrim.opacity(0.92), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            if let kicker {
                Text(kicker)
                    .textRole(.caption2)
                    .textCase(.uppercase)
                    .tracking(1.6)
                    // Fixed light on a fixed dark scrim, in every theme: the scrim is dark
                    // on paper as well as at night, so a palette colour that flips with the
                    // theme would be unreadable in half of them.
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Text(publication.displayTitle)
                .textRole(.display)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.7)

            if let line {
                Text(line)
                    .textRole(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(StoryArcSpace.lg)
        .frame(width: width, alignment: .leading)
    }

    /// The small line above the title: what this issue belongs to.
    ///
    /// The series where there is one, because that is what a reader recognises before they
    /// recognise an issue title. Otherwise whoever published it, and otherwise nothing —
    /// an uppercase "CBZ" over someone's artwork is a file extension wearing a kicker.
    private var kicker: String? {
        if let series = publication.series, series != publication.displayTitle { return series }
        return publication.publisher
    }

    /// What is left to read, or why it cannot be read right now.
    private var line: String? {
        guard isReadable else {
            return String(localized: "home.unavailable", bundle: .module, locale: .storyArc)
        }
        return model.remaining(of: publication)
    }

    private var spoken: String {
        [publication.displayTitle, kicker, line].compactMap { $0 }.joined(separator: ", ")
    }
}
