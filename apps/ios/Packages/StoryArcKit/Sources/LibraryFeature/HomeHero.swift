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

    /// The widest a card grows. A phone never reaches either number.
    ///
    /// Two of them by window width, which is §3.11's "fewer, larger, more confident covers,
    /// not the same phone lattice widened". One cap sized for a phone left a 13-inch iPad
    /// showing a hero the size of a paperback with half the window empty beside it; the
    /// wide cap is still well short of a frame the size of a page, which is what the single
    /// number was protecting against in the first place.
    ///
    /// Measured rather than read from `horizontalSizeClass`, for the reason ``CoverGrid``
    /// gives: the same iPad hands this shelf a good 300 pt less once the sidebar is out,
    /// and less again in a Split View slot. The input is the width the shelf actually got.
    private static let widestCard: CGFloat = 420
    private static let widestCardInAWideWindow: CGFloat = 560

    /// Cover proportions, opened out a little. Comic trim is 2:3; the card is 4:5, which
    /// is enough room for the caption without either cropping the art or leaving a band of
    /// wash under every cover.
    private static let cardAspect: CGFloat = 1.25

    @State private var available: CGFloat = 0

    /// The cap this window earns.
    private var widest: CGFloat {
        available >= StoryArcWindowClass.sidebarWidthThreshold
            ? Self.widestCardInAWideWindow
            : Self.widestCard
    }

    private var cardWidth: CGFloat {
        min(max(available * Self.cardShare, 0), widest)
    }

    /// The lone card takes the width between the gutters, because there is nothing beside
    /// it for a peek to promise.
    private var soloWidth: CGFloat {
        min(max(available - StoryArcSpace.gutter * 2, 0), widest)
    }

    var body: some View {
        Group {
            // `home-screen`: with fewer in progress than a carousel needs to make sense,
            // Keep reading "presents as a single large card rather than as a carousel of
            // one". One is that case. Two is not — collapsing there would hide a
            // publication the reader is in the middle of, which is the thing this section
            // exists to never do.
            if publications.count == 1, let only = publications.first {
                card(only, width: soloWidth)
                    .padding(.horizontal, StoryArcSpace.gutter)
            } else {
                carousel
            }
        }
        // Full width *before* the measurement, and that order is the whole of it: measuring
        // a container that a card had already shrunk made the card's width an input to
        // itself, and the loop settled on a card two thirds of the size it was asked for.
        .frame(maxWidth: .infinity, alignment: .leading)
        // §3.11: the hero's art mirrors and blurs outward under the floating glass sidebar,
        // so the surface reads as one thing the chrome is sitting on rather than as a card
        // inside a frame. It is the single detail that most makes a screen read as iPadOS
        // 26, and it is what the publication-detail hero already does. A phone has nothing
        // for it to extend under and the modifier is inert there — which is why this is one
        // line and not a size-class branch.
        .backgroundExtensionEffect()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: StoryArcSpace.md) {
                ForEach(publications) { publication in
                    card(publication, width: cardWidth)
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

    private func card(_ publication: Publication, width: CGFloat) -> some View {
        HomeHeroCard(
            publication: publication,
            model: model,
            width: width,
            height: width * Self.cardAspect,
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
            // One constant for Home and the shelf alike — see ``LibraryMarks/awayOpacity``.
            .opacity(isReadable ? 1 : LibraryMarks.awayOpacity)
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

            if let byline {
                Text(byline)
                    .textRole(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }

            if let fraction {
                progressBar(fraction)
            }

            if let line {
                Text(line)
                    .textRole(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(StoryArcSpace.lg)
        .frame(width: width, alignment: .leading)
        // The one place on this screen where text stops growing, and the reason is what
        // happens without it: the card is a fixed frame over artwork, so past
        // `accessibility1` the title hits its scale floor while the caption under it keeps
        // growing, and the smallest words on the card become the title of the book. The
        // heading above scales without limit, and so does the list it leads to, where the
        // same titles are set as ordinary text with room to wrap.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// What this issue belongs to. ``HomeCardIdentity/kicker(of:)``.
    private var kicker: String? { HomeCardIdentity.kicker(of: publication) }

    /// Who wrote it, where the card has room to say so. ``HomeCardIdentity/byline(of:)``.
    private var byline: String? { HomeCardIdentity.byline(of: publication) }

    /// How far through, as a thing to see rather than a thing to read.
    ///
    /// `nil` where ``LibraryModel/readFraction(of:)`` is: a bar at zero under every card
    /// would be a promise of information the app does not have. An unreachable publication
    /// keeps its bar — the reader's position is still true, and taking it away would make
    /// a Wi-Fi drop look like lost reading, which is what the dimming rule exists to avoid.
    private var fraction: Double? { model.readFraction(of: publication) }

    /// The bar itself: fixed light on the scrim, like the words above it.
    ///
    /// Hand-drawn rather than a `ProgressView`, because a `.linear` progress view takes the
    /// tint from the environment and this bar sits on a dark scrim in every theme — the
    /// accent that is legible on paper is not legible here. Hidden from assistive
    /// technology: the line under it already says what it shows, and a bar that announced
    /// "58 per cent" beside "42 pages left" would say the same thing twice in two units.
    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.28))
                Capsule()
                    .fill(.white)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: Self.progressBarHeight)
        .accessibilityHidden(true)
    }

    /// Thin enough to read as a rule under the byline rather than as a control.
    private static let progressBarHeight: CGFloat = 4

    /// What is left to read, or why it cannot be read right now.
    private var line: String? {
        guard isReadable else {
            return String(localized: "home.unavailable", bundle: .module, locale: .storyArc)
        }
        return model.remaining(of: publication)
    }

    private var spoken: String {
        [publication.displayTitle, byline, kicker, line].compactMap { $0 }.joined(separator: ", ")
    }
}
