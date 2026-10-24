public import SwiftUI

public import CoreGraphics
public import StoryArcCore

internal import DesignSystem
#if !canImport(UIKit) && canImport(AppKit)
internal import AppKit
#endif

/// The player's artwork: the library's own cover, or the well every other surface draws when
/// there is none.
///
/// Task 16.10, `audio-playback`'s *A publication with no cover*: the player "draws the same
/// coverless treatment every other surface draws … rather than a treatment of the player's
/// own" — which is one half of that scenario. The other half is that a publication **with** a
/// cover gets it, and this used to draw the well always: no cover is read out of an audiobook
/// yet (`PublicationIndexer.audiobook`), but an EPUB being read aloud has one the library
/// already decoded, and the player ignored it.
public struct PlayerArtwork: View {
    private let format: PublicationFormat
    /// The library's cover, already resolved. `nil` draws the well — absent, not a second
    /// attempt to fetch one from a view that has no library to ask.
    private let cover: CGImage?

    public init(format: PublicationFormat, cover: CGImage? = nil) {
        self.format = format
        self.cover = cover
    }

    public var body: some View {
        Group {
            if let cover {
                Image(decorative: cover, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                CoverlessWell(format: format)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(.rect(cornerRadius: StoryArcRadius.lg, style: .continuous))
    }
}

extension PlayerArtwork {
    /// How tall the artwork may be: whatever keeps the transport on the first screen, never
    /// below 120 points, and `nil` before the screen is measured.
    ///
    /// `audio-playback`: "no transport control is pushed off the screen". On the outer display of
    /// an iPhone Duo (678 points tall) a 480-point cover put the transport under the bottom edge.
    /// Android's `playerArtworkMax` holds the same rule. The two `xl`s are the padding above the
    /// cover and the gap below it.
    static func maxHeight(viewport: CGFloat, underneath: CGFloat) -> CGFloat? {
        guard viewport > 0 else { return nil }
        return max(viewport - underneath - 2 * StoryArcSpace.xl, 120)
    }
}

@MainActor
public enum PlayerArtworkImage {

    public static let side: CGFloat = 512

    public static func png(format: PublicationFormat, cover: CGImage? = nil) -> Data? {
        let renderer = ImageRenderer(
            content: PlayerArtwork(format: format, cover: cover)
                .frame(width: side, height: side)
                .environment(\.theme, Theme(palette: .dark))
        )
        renderer.scale = 1
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #else
        // The Mac's Now Playing panel (`desktop-clients` wave 4): the same well, as PNG bytes.
        return renderer.cgImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        #endif
    }
}
