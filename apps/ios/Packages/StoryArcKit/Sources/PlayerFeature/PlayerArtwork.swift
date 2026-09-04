public import SwiftUI

public import StoryArcCore

internal import DesignSystem

/// The player's artwork: the shared coverless well, at the player's own shape.
///
/// `audio-playback`, *A publication with no cover*: the player "draws the same coverless
/// treatment every other surface draws … rather than a generic glyph", and "the system's own
/// media controls get that same artwork, because a lock screen showing a headphones symbol is
/// the one place a listener looks for an hour".
///
/// **It now literally is the same view.** `FullPlayerView` drew `Image(systemName:
/// "headphones")` with a comment claiming it was "the same placeholder the library draws";
/// that was replaced by a title set into a rounded rectangle here, which was a second
/// implementation of the treatment rather than the treatment — the compromise
/// `audiobooks-and-playback` §4.4b recorded, because ``CoverlessWell`` was in `LibraryFeature`
/// and `Package.swift` forbids one feature depending on another. The well is in
/// `DesignSystem` now, which `PlayerFeature` already depends on, so this file is a shape and
/// nothing else.
///
/// The glyph is chosen from the format rather than fixed, which is what makes the spec's
/// "rather than a generic glyph" true of a read-aloud EPUB as well as of an M4B: the two are
/// one player and two different things to look at.
///
/// **A square rather than 2:3, and that is not a second treatment.** An audiobook's artwork is
/// square everywhere a listener has seen one, and the rendered image below is what a lock
/// screen and a car display are handed. The well fills whatever shape it is given and sizes
/// its glyph off that shape, so the same view is right at 146 pt in a grid cell and at 320 pt
/// here.
public struct PlayerArtwork: View {
    private let format: PublicationFormat

    public init(format: PublicationFormat) {
        self.format = format
    }

    public var body: some View {
        CoverlessWell(format: format)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: StoryArcRadius.lg, style: .continuous))
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
///
/// The title is not in the picture and does not need to be: the lock screen sets
/// `MPMediaItemPropertyTitle` beside the artwork, the same way every surface in the app states
/// the title beside the well rather than inside it.
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
    /// - Parameter format: the publication's format, which chooses the glyph and names itself
    ///   under it.
    ///
    /// **Drawn in the dark palette rather than the reader's, deliberately.** The system shows
    /// this over its own material, and an image that followed the app's appearance would have to
    /// be re-rendered and re-published every time a reader flipped it mid-book — a picture on a
    /// lock screen is not a surface that participates in the app's theme.
    ///
    /// - Returns: PNG bytes, or `nil` where the renderer produced nothing — a `nil` the caller
    ///   publishes as *no artwork* rather than as a blank square.
    public static func png(format: PublicationFormat) -> Data? {
        #if canImport(UIKit)
        let renderer = ImageRenderer(
            content: PlayerArtwork(format: format)
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
