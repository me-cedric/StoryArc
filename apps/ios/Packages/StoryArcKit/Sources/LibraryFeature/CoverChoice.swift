public import Foundation

internal import CoreGraphics
internal import Formats
public import StoryArcCore

/// What the reader can do about a publication's cover.
///
/// Tasks 2.2 and 2.4 of `cover-for-every-publication`, as model work rather than as view
/// work, so the rules can be asserted without a window. The view beside this —
/// ``DetailCoverChoice`` — is the picker and two labels; everything that decides what the
/// shelf draws next is here.
extension LibraryModel {

    /// Whether the reader has chosen this publication's cover themselves.
    public func hasChosenCover(for publication: Publication) -> Bool {
        CoverOverrideStore().file(for: publication) != nil
    }

    /// Whether moving this publication would lose the cover the reader chose.
    ///
    /// `cover-art`'s *A publication with no digest*: a folder of images and a server row
    /// carry no content digest, so their override is filed under the stable identifier —
    /// which is the path — and a move breaks it. The page says so plainly rather than
    /// letting the choice disappear without explanation.
    public func chosenCoverIsTiedToPath(for publication: Publication) -> Bool {
        CoverOverrideStore().keyKind(for: publication) == .stableIdentifier
    }

    /// Records a picture the reader picked as this publication's cover.
    ///
    /// The picture is cropped to the cover shape first, because the ladder's other rungs all
    /// answer with artwork that already is that shape and a photograph is not.
    ///
    /// - Returns: whether the picture was stored. False is a picture this device cannot
    ///   decode, or a write that failed; the caller tells the reader rather than leaving a
    ///   button that appears to do nothing.
    @discardableResult
    public func setCover(_ picture: Data, for publication: Publication) -> Bool {
        guard let shaped = CoverArtwork.coverShaped(picture) else { return false }
        guard CoverOverrideStore().store(shaped, for: publication) != nil else { return false }
        forgetDrawnCover(of: publication)
        return true
    }

    /// Removes the cover the reader chose, and deletes the image.
    ///
    /// The ladder resolves the publication's cover again from the rung below on the next
    /// draw, which is what `cover-art`'s *Undoing the choice* asks for.
    public func removeChosenCover(for publication: Publication) {
        CoverOverrideStore().remove(for: publication)
        forgetDrawnCover(of: publication)
    }

    /// Drops every copy of this publication's artwork that something has already drawn.
    ///
    /// Both caches, not one. ``covers`` is what the shelf is holding this launch, and
    /// ``CoverCache`` is what it will read on the next one — leaving either behind shows the
    /// reader the cover they just replaced, which reads as the choice not having worked.
    private func forgetDrawnCover(of publication: Publication) {
        covers[publication.id] = nil
        CoverCache().removeEverySize(for: publication.id)
    }
}
