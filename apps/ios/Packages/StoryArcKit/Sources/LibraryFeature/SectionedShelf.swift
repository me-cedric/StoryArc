internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// A long shelf with structure: one continuous grid, divided by headings that stay put
/// while their section is on screen.
///
/// `library-browsing` asks for exactly that, and `CoverGrid` cannot give it — its grid lives
/// inside its own `ScrollView`, and a pinned header has to sit in the same lazy stack as the
/// cells it heads. So this is the sectioned shelf and `CoverGrid` stays the uniform one:
/// short libraries, the on-device destination and search results, none of which divide.
///
/// The cells are `CoverCell`, unchanged. The one duplication with `CoverGrid` is the column
/// rule below, which is a `design.md` sentence rather than a layout opinion; the slice that
/// owns `CoverGrid` should lift it into one place both can read.
struct SectionedShelf: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let sections: [LibrarySection]
    let model: LibraryModel
    let onOpen: (Publication) -> Void

    /// What the reader has picked, or `nil` when they are not picking.
    var selection: Set<String>?
    var onToggle: (Publication) -> Void = { _ in }

    /// Whether a publication can be opened right now.
    ///
    /// `library-browsing`: one that is neither on the device nor currently reachable "is
    /// dimmed and still selectable, so it can be inspected, downloaded later, or added to a
    /// shelf", and "dimming is the only difference — it is not moved, grouped apart, or
    /// badged as an error". A library that shrank when the Wi-Fi dropped would read as data
    /// loss, which is the whole reason this is opacity and not a filter.
    var isReadableNow: (Publication) -> Bool = { _ in true }

    /// How much room the shelf itself has. Measured for the reason `CoverGrid` measures it:
    /// a size class is coarse, and a shelf pushed into a narrower column is not a phone.
    @State private var width: CGFloat = 0

    /// The width at or above which the shelf stops being a widened phone.
    private static let confidentShelfWidth: CGFloat = 900

    /// `design.md`: "Minimum cover width scales by size class: 104 / 132 / 158 pt."
    private var minimumWidth: CGFloat {
        switch width {
        case ..<StoryArcWindowClass.sidebarWidthThreshold: 104
        case ..<Self.confidentShelfWidth: 132
        default: 158
        }
    }

    /// Headroom over the minimum, so the last column grows into the leftover instead of
    /// leaving a ragged margin down the trailing edge.
    private var maximumWidth: CGFloat { (minimumWidth * 1.6).rounded() }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        grid(section.publications)
                    } header: {
                        SectionHeading(title: section.title)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private func grid(_ items: [Publication]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: minimumWidth, maximum: maximumWidth),
                    spacing: StoryArcSpace.md,
                    // Top, not the default centre: a cell is a cover with a caption under
                    // it, and centring would float every cover to a different height.
                    alignment: .top
                )
            ],
            spacing: StoryArcSpace.lg
        ) {
            ForEach(items) { publication in
                let readable = isReadableNow(publication)
                CoverCell(
                    publication: publication,
                    model: model,
                    onOpen: onOpen,
                    // Pixels, not points: a cover decoded at point size is blurry on every
                    // device made since 2010.
                    maxPixelSize: Int(maximumWidth * displayScale),
                    isPicked: selection?.contains(publication.id),
                    onToggle: onToggle
                )
                .opacity(readable ? 1 : 0.45)
                // Dimming is invisible to VoiceOver, and "why can I not open this" is the
                // only question it raises. Said rather than shown as well as shown.
                .accessibilityHint(readable ? Text("") : Text("library.cell.unavailable", bundle: .module))
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.bottom, StoryArcSpace.lg)
    }
}

/// One heading over its part of the shelf.
///
/// It sits on glass because the covers scroll *under* it: `native-experience` puts floating
/// chrome on Liquid Glass, and a heading on an opaque bar would cut a hard line across the
/// artwork every time a section passed behind it.
struct SectionHeading: View {
    @Environment(\.theme) private var theme

    let title: String

    var body: some View {
        Text(title)
            .textRole(.headline)
            .foregroundStyle(theme.palette.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.sm)
            .storyArcGlass(in: Rectangle())
            .accessibilityAddTraits(.isHeader)
    }
}
