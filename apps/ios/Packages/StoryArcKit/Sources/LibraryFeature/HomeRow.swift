internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// A titled section of Home whose heading is the way to the whole of it.
///
/// `home-screen`: "when a shelf holds more than it can show, its heading leads to the full
/// list", and "no shelf silently truncates without offering the rest". So the heading is
/// the link — the pattern Apple Music uses on the tab this screen is modelled on, and one
/// SwiftUI has no dedicated API for: a `NavigationLink` around a title and a chevron is
/// how Apple builds it too.
struct HomeSection<Content: View, Destination: View>: View {
    @Environment(\.theme) private var theme

    let title: Text
    private let destination: () -> Destination
    private let content: () -> Content

    init(
        title: Text,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.destination = destination
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            NavigationLink(destination: destination) {
                HStack(spacing: StoryArcSpace.xs) {
                    title
                        .textRole(.title3)
                        .foregroundStyle(theme.palette.textPrimary)

                    Image(systemName: "chevron.right")
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textTertiary)

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
                .padding(.horizontal, StoryArcSpace.gutter)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("home.seeAll", bundle: .module))

            content()
        }
    }
}

/// One horizontal run of covers.
///
/// A shelf rather than a grid: Home is never exhaustive, so a section that ran out of
/// screen would be claiming to be the library. The cells stay plain — cover, title, and at
/// most one line under it — because the cover is the interface and a Home card that grew
/// badges would be competing with the art it is made of.
struct HomeShelfRow: View {
    let publications: [Publication]
    let model: LibraryModel

    /// The width at or above which covers stop being a widened phone's.
    ///
    /// `design.md`: "Minimum cover width scales by size class: 104 / 132 / 158 pt." A shelf
    /// takes the upper two — a Home shelf of 104 pt covers would be a strip of stamps.
    @State private var available: CGFloat = 0

    private var coverWidth: CGFloat {
        available >= StoryArcWindowClass.sidebarWidthThreshold ? 158 : 132
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: StoryArcSpace.coverGap) {
                ForEach(publications) { publication in
                    HomeShelfCard(
                        publication: publication,
                        model: model,
                        width: coverWidth
                    )
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, StoryArcSpace.gutter, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
    }
}

/// One publication on a shelf.
private struct HomeShelfCard: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    let width: CGFloat

    private var isReadable: Bool { model.isReadableNow(publication) }

    /// The card, and where it leads.
    ///
    /// To the publication's page. These are the *Up next*, *Recently added* and *Finished*
    /// shelves — none of them offers to resume anything, and `publication-detail` sends
    /// every cover that is not a resume affordance to the page. `Keep reading` is the
    /// affordance that does resume, and it is ``HomeHero``, which still opens the book.
    ///
    /// A publication that cannot be opened right now stays on the shelf, dimmed, and does
    /// not lead anywhere: `home-screen` requires it kept and stated, and the page's own
    /// primary action is the thing that cannot be honoured, so there is nothing there to
    /// offer yet. That is the one place this differs from the library's grid, where the same
    /// publication is dimmed for availability rather than refused for format.
    var body: some View {
        Group {
            if isReadable {
                NavigationLink(value: PublicationRoute(publication)) { card }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([publication.displayTitle, subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isReadable ? .isButton : [])
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            HomeArtwork(publication: publication, model: model, width: width)
                // 2:3 is the comic and book proportion, and fixing it here means a card
                // reserves its space before its cover arrives.
                .frame(width: width, height: width * 3 / 2)
                .clipShape(.rect(cornerRadius: StoryArcRadius.cover))
                .overlay {
                    RoundedRectangle(cornerRadius: StoryArcRadius.cover)
                        .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    if let fraction = model.readFraction(of: publication) {
                        ProgressBar(fraction: fraction)
                    }
                }

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(publication.displayTitle)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        // Dimmed, never dropped: `home-screen` keeps what cannot be opened right now on
        // the shelf and says so, because a shelf that shrinks with the Wi-Fi reads as data
        // loss to a reader who did not lose anything.
        //
        // ``LibraryMarks/awayOpacity``, not a number of its own: Home dimmed to 0.55 and the
        // shelf to 0.45, so the same unreachable book was two brightnesses depending on which
        // screen a reader was looking at. Android has carried one constant for both.
        .opacity(isReadable ? 1 : LibraryMarks.awayOpacity)
        .contentShape(.rect)
    }

    /// The second line: what tells this card from its neighbours, or why it is dimmed.
    private var subtitle: String? {
        guard isReadable else {
            return String(localized: "home.unavailable", bundle: .module, locale: .storyArc)
        }
        // ``seriesLine(for:)`` rather than the composition written out again. This card was
        // the one surface that had always got this right, and the rule was lifted out of it;
        // keeping a private copy here is how the shelf and the card would come to disagree
        // about it a second time.
        return seriesLine(for: publication) ?? publication.authors.first
    }
}
