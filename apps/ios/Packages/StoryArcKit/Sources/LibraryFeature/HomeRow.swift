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

/// A heading over a section that has nowhere further to go.
///
/// The finished timeline's months, which are not a filter the library can be put into:
/// there is no "everything I finished in March" shelf to lead to, and a chevron that led
/// back to the same list would be a promise the screen cannot keep.
struct HomeHeading: View {
    @Environment(\.theme) private var theme

    let title: Text

    var body: some View {
        title
            .textRole(.title3)
            .foregroundStyle(theme.palette.textPrimary)
            .padding(.horizontal, StoryArcSpace.gutter)
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
    let onOpen: (Publication) -> Void

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
                        width: coverWidth,
                        onOpen: onOpen
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
    let onOpen: (Publication) -> Void

    private var isReadable: Bool { model.isReadableNow(publication) }

    var body: some View {
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
        .opacity(isReadable ? 1 : 0.55)
        .contentShape(.rect)
        .onTapGesture { if isReadable { onOpen(publication) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([publication.displayTitle, subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isReadable ? .isButton : [])
    }

    /// The second line: what tells this card from its neighbours, or why it is dimmed.
    private var subtitle: String? {
        guard isReadable else {
            return String(localized: "home.unavailable", bundle: .module, locale: .storyArc)
        }
        if let series = publication.series {
            let line = publication.number.map { "\(series) #\($0)" } ?? series
            // A guessed title is often the series and the issue joined back together, and
            // a card that printed the same words twice would look like a rendering fault
            // rather than a second fact.
            if line.caseInsensitiveCompare(publication.displayTitle) != .orderedSame { return line }
        }
        return publication.authors.first
    }
}
