internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The artwork, at the size the direction asks for: the largest thing on the page.
///
/// Shown whole rather than cropped, which is `publication-detail`'s wording and the same
/// rule the grid cell already follows — a manga volume and a square EPUB cover are not the
/// comic trim, and cutting their edges off is a worse answer than letterboxing them onto
/// the sunken surface behind.
///
/// The wash is not applied here. It is behind the whole page, and this sits on it: the
/// delta requires that "the cover itself is not tinted, recoloured or dimmed by it", so the
/// one thing on the screen that must stay exactly as printed is the one thing the colour
/// taken from it never touches.
struct DetailHero: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    let publication: Publication
    /// `nil` until the cover has been decoded, and for a publication that has none.
    let cover: CGImage?

    var body: some View {
        artwork
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: maximumWidth)
            .clipShape(.rect(cornerRadius: StoryArcRadius.md))
            .overlay {
                // The same hairline the grid puts round a cover, for the same reason: a
                // pale cover on a pale surface has no edge of its own.
                RoundedRectangle(cornerRadius: StoryArcRadius.md)
                    .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
            }
            .shadow(color: theme.palette.scrim.opacity(0.35), radius: 24, y: 12)
            .frame(maxWidth: .infinity)
            .padding(.top, StoryArcSpace.lg)
            // §3.4: on iPad the art mirrors and blurs under the floating sidebar, so the
            // page reads as one surface rather than as a card inside a chrome frame. A
            // phone has nothing for it to extend under, and the modifier is inert there.
            .backgroundExtensionEffect()
            // One image with no label. The title is the next thing in the reading order and
            // it says everything this could; a second announcement of the same words is
            // noise to anyone listening to the page rather than looking at it.
            .accessibilityHidden(true)
    }

    /// How wide the cover is allowed to get.
    ///
    /// The constraint is the fold rather than the margin. The cover has to lead *and* leave
    /// the title and the primary action on the first screen: sized to the full width of a
    /// phone it is 2:3 of 393 pt, which is most of the screen, and what a reader lands on is
    /// a picture with nothing to do on it. Wider on an iPad, where there is room for both.
    private var maximumWidth: CGFloat {
        sizeClass == .regular ? 300 : 220
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            ZStack {
                theme.palette.surfaceSunken
                Image(decorative: cover, scale: 1)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            // The app's own placeholder, per the delta: legible, no colour derived from it,
            // and the title never rendered over an image that failed to load — because
            // there is no image here at all.
            //
            // The glyph and the format were written out here, which is how this page came to
            // give an *audiobook* a book: `book.closed` was hard-coded. ``CoverlessWell`` is
            // the same two things chosen from the format, drawn on every surface that has a
            // cover-shaped hole in it.
            CoverlessWell(format: publication.format)
        }
    }
}

/// Title, series, number and year, as one object.
///
/// §3.4: the title in the editorial face with the metadata in a tight stack at `xs`, so the
/// three read as one thing rather than as three rows of a table. A line the publication does
/// not carry is absent rather than empty — the delta refuses a placeholder, and a screen
/// that says "Year: —" has invented a fact about the book.
struct DetailTitleBlock: View {
    @Environment(\.theme) private var theme

    /// The editorial face, scaled.
    ///
    /// `textRole(.display)` is the serif voice this title wants, and it is the one role in
    /// the scale that takes a **fixed** point size — every other role is built on a text
    /// style and grows with Dynamic Type. At the accessibility sizes that leaves the title
    /// *smaller* than the series line under it, which is the hierarchy inverted on the one
    /// screen `publication-detail` singles out as "where a hero screen breaks first".
    ///
    /// So the size is scaled here rather than the role being changed: the design system's
    /// fixed serif is shared by every screen that uses it, and one screen is not the place
    /// to decide that for all of them. Reported in the handoff as a systemic finding.
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = StoryArcType.displaySize

    let publication: Publication

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            Text(publication.displayTitle)
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .tracking(StoryArcType.displayTracking)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let series = seriesLine(for: publication) {
                Text(series)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let secondary = secondaryLine {
                Text(secondary)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // The series line is ``seriesLine(for:)`` — the shelf's own rule, not a second copy of
    // it. This block used to carry the shape the shelf was fixed out of: it compared the
    // **bare** series against the title and then drew the **composed** `"<series> #<number>"`,
    // so the page for a publication titled `Ashfall #1` set the title in the editorial face
    // and repeated `Ashfall #1` underneath it in the headline role. The hero is where that
    // reads worst, because both lines are large.

    /// Author and year, joined only where both exist — ``detailSecondaryLine(for:)``.
    ///
    /// Free and pure there rather than computed here, so the delta's "absent rather than
    /// shown empty" is a test instead of a reading of the `if let` above it.
    private var secondaryLine: String? { detailSecondaryLine(for: publication) }
}
