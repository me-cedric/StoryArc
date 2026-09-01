public import SwiftUI

internal import DesignSystem

/// The player's artwork: the title set into a cover-shaped well.
///
/// `audio-playback`, *A publication with no cover*:
///
/// > **THEN** it draws the same coverless treatment every other surface draws — the title set
/// > as artwork — rather than a generic glyph
/// > **AND** the system's own media controls get that same artwork, because a lock screen
/// > showing a headphones symbol is the one place a listener looks for an hour
///
/// `FullPlayerView` drew `Image(systemName: "headphones")` and its own comment claimed that was
/// "the same placeholder the library draws". **It was not** — the library draws `CoverlessWell`,
/// which sets the title into the well — and the lock screen inherited the glyph.
///
/// **Why this is not `CoverlessWell` itself, which would be better.** That view lives in
/// `LibraryFeature`, and `Package.swift` records the rule it would break: "one module per
/// screen area, and no feature depends on another". Its right home is `DesignSystem`, which
/// both features already depend on and where the well would need no new module edge at all —
/// that move is a follow-up, and until it happens this is the same treatment drawn where the
/// player can reach it.
///
/// **One difference, and it is the well's own size that decides it.** `CoverlessWell` drops the
/// title at an accessibility text size, because a `headline` in a 146 pt grid cell holds part of
/// one word — `Broken Transfer` becomes `Bro…`, which identifies nothing. This well is 320 pt,
/// more than twice as tall, and holds four lines of the largest accessibility size; and the one
/// place the title cannot be dropped is the rendered image below, where a lock screen has no
/// caption underneath it and no text size at all. So it is always drawn.
///
/// The format is not named here, which is `HomeArtwork`'s variant of the same well: "why is
/// there no picture" is a question the publication's own page answers, and the player has room
/// for the chapter instead.
public struct PlayerArtwork: View {
    @Environment(\.theme) private var theme

    private let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: StoryArcRadius.lg, style: .continuous)
            .fill(theme.palette.surfaceRaised)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Text(title)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(StoryArcSpace.md)
            }
    }
}

/// The same artwork as pixels, for the system's own media controls.
///
/// `Playback` has no SwiftUI and must not — `Formats` depends on it, and a parser has no
/// business linking a design system — so the picture is drawn here, where the treatment lives,
/// and carried to `NowPlaying` through ``PlayerCentre/onArtwork`` as the one thing both a
/// SwiftUI view and an `MPMediaItemArtwork` can hold.
///
/// **Rendered from the same view the player draws**, rather than re-drawn in Core Graphics: a
/// second implementation of the treatment is a second thing to keep in step, and the spec asks
/// for "that same artwork" rather than a similar one.
@MainActor
public enum PlayerArtworkImage {

    /// How large the picture is rendered.
    ///
    /// One size, and generous: `MPMediaItemArtwork` is asked for a picture at whatever size the
    /// lock screen, Control Centre or a car display wants, and the system scales one bitmap down
    /// far better than it scales a small one up.
    public static let side: CGFloat = 512

    /// The artwork for a publication with no cover of its own.
    ///
    /// - Parameter title: what the well is set with.
    ///
    /// **Drawn in the dark palette rather than the reader's, deliberately.** The system shows
    /// this over its own material, and an image that followed the app's appearance would have to
    /// be re-rendered and re-published every time a reader flipped it mid-book — a picture on a
    /// lock screen is not a surface that participates in the app's theme.
    ///
    /// - Returns: PNG bytes, or `nil` where the renderer produced nothing — a `nil` the caller
    ///   publishes as *no artwork* rather than as a blank square.
    public static func png(title: String) -> Data? {
        #if canImport(UIKit)
        let renderer = ImageRenderer(
            content: PlayerArtwork(title: title)
                .frame(width: side, height: side)
                .environment(\.theme, Theme(palette: .dark))
        )
        // One point to one pixel: `side` is already in pixels for this purpose, and the default
        // scale would produce a 1536-square image for a 512-square request.
        renderer.scale = 1
        return renderer.uiImage?.pngData()
        #else
        nil
        #endif
    }
}
