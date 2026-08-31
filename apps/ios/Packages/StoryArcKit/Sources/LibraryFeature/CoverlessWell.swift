internal import SwiftUI

/// What a cover-shaped well draws when the publication has no artwork.
///
/// Plenty of EPUBs carry no cover at all, and a wall of identical grey cards labelled with
/// a format has nothing in it that tells one book from another — so both surfaces that draw
/// a well, ``CoverCell`` in the grid and ``HomeArtwork`` on a shelf, set the title into it
/// as a stand-in for the missing art.
///
/// **Set type is not a font size the app may choose.** `design.md` §3: the token sizes "are
/// the size at the default setting, not a fixed size", and both wells carried
/// `minimumScaleFactor(0.6)` — which is a fixed size wearing a disguise. It shrinks the
/// reader's chosen text by up to forty per cent, and it shrinks it *most* for the reader
/// who asked for the largest, which is the one person it must not do that to. Apple's own
/// accessibility audit reports it as `Dynamic Type font sizes are partially unsupported`,
/// and the audit is right: that is the whole of the finding.
///
/// So the scale factor goes, and the well has to answer the question the scale factor was
/// hiding: what does a stand-in title do when the reader's type no longer fits the well?
///
/// It stops being a stand-in. At an accessibility text size a `headline` is large enough
/// that a 146 pt well holds part of one word — `Broken Transfer` becomes `Bro…`, which
/// identifies nothing and is not artwork either. And the title is not lost by dropping it:
/// **both** wells are drawn directly above a caption that states the same title, in full, at
/// exactly the size the reader asked for. The format label stays, so the well still answers
/// "why is there no picture here".
///
/// Below that the title is drawn at the reader's own size, wrapping to as many lines as the
/// well can hold and truncating if it must — never scaled down to fit.
///
/// Free and pure so the rule can be asserted without a window, and shared so the grid and
/// the shelf cannot come to disagree about it: they already carried two copies of the same
/// `minimumScaleFactor(0.6)`, and a rule copied is a rule that drifts.
///
/// - Parameter textSize: how large the reader has asked for text to be.
/// - Returns: whether the well draws the publication's title as its stand-in artwork.
func coverlessWellDrawsTitle(at textSize: DynamicTypeSize) -> Bool {
    !textSize.isAccessibilitySize
}
