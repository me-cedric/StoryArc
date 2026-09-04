public import SwiftUI

public import StoryArcCore

/// What a cover-shaped well draws when the publication has no artwork.
///
/// **One treatment, and it lives here so that it can be one.** The September sweep found a
/// missing cover drawn three unrelated ways: its own title on the shelf
/// (`ios-library-grid.png`), a book glyph with the format on the publication page
/// (`ios-detail-no-cover.png`), and a flat grey square with the title in it in the player
/// (`ios-player-sleep-sheet.png`) — and an *audiobook* got the book glyph too. "The app says
/// the artwork is the interface; this is what it does when there is none, in three unrelated
/// ways."
///
/// The view was in `LibraryFeature`, which is why the player could not use it: `Package.swift`
/// records that "no feature depends on another", so `PlayerFeature` drew its own. `DesignSystem`
/// is the home `audiobooks-and-playback` §4.4b named for it, and `LibraryFeature`,
/// `PlayerFeature` and the app target already all depend on it — so the move needs no new
/// module edge, only the file.
///
/// ## Why the glyph and the format, and not the title
///
/// The well used to set the publication's **title** into itself, on the argument that "a wall
/// of identical grey cards labelled with a format has nothing in it that tells one book from
/// another". That argument holds for the well considered alone and not for the screens it is
/// on: **every surface that draws this well already states the title beside it.** The shelf
/// cell draws it as the caption underneath — so a cover-less cell said `Foreign Codec` inside
/// the well and `Foreign Codec` again under it, which is what the sweep photographed. The
/// publication page draws it in the editorial face directly below. The player draws it in
/// `title2` under the artwork, and the lock screen puts `MPMediaItemPropertyTitle` next to it.
///
/// So the title in the well was never the thing that distinguished one card from another; it
/// was the caption repeated at a smaller size. What the well can say that nothing beside it
/// says is **what kind of thing this is** — which is also the sweep's third complaint, that an
/// audiobook was given a book glyph. The format's own symbol answers it at a glance and the
/// format's name answers it in words, which is the pairing `design.md` rule 2 asks for:
/// "never use colour as the sole carrier of state — pair it with an icon, a label or a shape".
///
/// It also retires a Dynamic Type rule the well should never have needed. The title had to be
/// *dropped* at an accessibility text size, because a `headline` in a 146 pt grid cell holds
/// part of one word — `Broken Transfer` became `Bro…`, which identifies nothing — so the well
/// drew one thing at ordinary sizes and another at large ones. A format name is four to nine
/// characters and wraps rather than truncating, so there is one treatment at every text size
/// as well as on every surface. Never a `minimumScaleFactor`: `design.md` §3 says the token
/// sizes "are the size at the default setting, not a fixed size", and a scale factor is a
/// fixed size wearing a disguise — Apple's own accessibility audit reported the two the well
/// used to carry as `Dynamic Type font sizes are partially unsupported`.
///
/// ## Why the glyph is sized off the well rather than given a point size
///
/// The same well is drawn at 146 pt in a grid cell, at 220–300 pt on a publication page and at
/// 320 pt in the player, and rendered at 512 pt for the lock screen. A fixed point size is
/// right for one of those and wrong for the rest, and a per-surface parameter is how three
/// surfaces come to disagree again. A share of the well's own shorter side is the same
/// decision at every size, and needs nothing from the caller.
public struct CoverlessWell: View {
    @Environment(\.theme) private var theme

    /// How much of the well's shorter side the glyph takes.
    ///
    /// A stand-in for artwork rather than an icon in a row: large enough to read as the
    /// subject of the well, small enough to leave the format's name clear of it at the
    /// largest text size.
    private static let glyphShare: CGFloat = 0.3

    private let format: PublicationFormat

    public init(format: PublicationFormat) {
        self.format = format
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: StoryArcSpace.xs) {
                Spacer(minLength: 0)
                Image(systemName: coverlessWellSymbol(for: format))
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.glyphSide(in: geometry.size))
                Spacer(minLength: 0)
                // The reader's own size, wrapping rather than shrinking. Two lines is what
                // `Audio folder` needs in a grid cell at an accessibility size; nothing this
                // app calls a format is longer than that.
                Text(format.displayName)
                    .textRole(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(theme.palette.textTertiary)
            .padding(StoryArcSpace.xs)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(theme.palette.surfaceRaised)
    }

    /// The glyph's side for a well of this size.
    ///
    /// Off the shorter side, so a square player well and a 2:3 grid cell resolve the same
    /// proportion rather than the square one growing a glyph two thirds as wide as itself.
    private static func glyphSide(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * glyphShare
    }
}

/// The symbol that stands in for a publication of this format.
///
/// `design.md` §8: SF Symbols, no custom icon set — "a user recognises the platform's share
/// icon instantly and would have to learn a custom one".
///
/// **Four glyphs for nine formats, and the grouping is the point.** What a reader needs from
/// a well with no artwork in it is what kind of thing this is: something to look at page by
/// page, something to read, a document, or something to listen to. Naming CBZ and CBT with
/// different pictures would be drawing the container rather than the publication — the *name*
/// underneath already carries that, and it is the half that can be exact.
///
/// The audio case is the one the sweep named: an audiobook was given `book.closed` on its own
/// page, "and an *audiobook* gets the book glyph too". A listener looking for a book they
/// listen to should not be shown a book they read.
///
/// Free and pure so the mapping can be asserted without a window — see `CoverlessWellTests`.
///
/// - Parameter format: the publication's format.
/// - Returns: the name of the SF Symbol the well draws.
public func coverlessWellSymbol(for format: PublicationFormat) -> String {
    switch format {
    case .cbz, .cbr, .cb7, .cbt, .imageFolder: "book.pages"
    case .epub: "book.closed"
    case .pdf: "doc.text"
    case .audiobook, .audioFolder: "headphones"
    }
}
