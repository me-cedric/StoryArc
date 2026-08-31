public import SwiftUI

public import StoryArcCore

internal import DesignSystem

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
public func coverlessWellDrawsTitle(at textSize: DynamicTypeSize) -> Bool {
    !textSize.isAccessibilitySize
}

/// The well itself, so that three surfaces draw one.
///
/// The rule above was shared and **the view was not**, which left the two wells this file's
/// own comment calls "two wells, one defect" still written out twice — and a third surface
/// with no well at all. The downloads destination draws a cover-shaped box on both
/// platforms and, when a publication has no artwork, drew nothing into it: not the title,
/// not the format, an empty rectangle. Nine of the twelve publications on a test device
/// carry no cover, so most of that screen was blank cards.
///
/// **No check caught it on this platform, and the reason is worth knowing.** The well is
/// `accessibilityHidden` and the caption below the cell carries the title, so the screen
/// reads correctly to VoiceOver whether or not anything is drawn in the box — Apple's audit
/// has one finding on Downloads and it is about contrast.
///
/// A first version of this comment claimed Android's own scanner had seen it. **That was not
/// verified and is probably false**: the two findings it named were `UNNAMED View` and
/// `SMALL View 114.3x14.1dp`, and 14 dp is a tenth the height of a cover cell — whatever they
/// were, they were not a well. A reviewer refused to repeat the claim, which was right.
///
/// So this defect was invisible to every automated check on both platforms and obvious to
/// anyone looking at the screen, which is exactly the case §6 of `AGENTS.md` asks for a
/// screenshot to catch. It went unnoticed until someone photographed the screen for an
/// unrelated reason.
///
/// So the well is a view now, and the surfaces ask for it rather than reproducing it. What
/// genuinely differs between them is one thing — whether the format is named — and the
/// layout follows from that rather than from three separate opinions: a well that names a
/// format has to keep its title clear of the label at the bottom, and a well that does not
/// simply centres it.
///
/// Public for the same reason ``coverMinimumWidth(shelfWidth:textSize:)`` is: the on-device
/// shelf is a grid of covers that lives in the app target, and a rule it cannot reach is a
/// rule it will reimplement.
public struct CoverlessWell: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var textSize

    private let title: String
    /// The format's name, or `nil` on a surface small enough that naming it crowds the well.
    private let format: String?

    public init(title: String, format: String?) {
        self.title = title
        self.format = format
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            theme.palette.surfaceRaised

            if coverlessWellDrawsTitle(at: textSize) {
                Text(title)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, StoryArcSpace.sm)
                    .frame(maxHeight: .infinity)
            }

            if let format {
                Text(format)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .padding(.bottom, StoryArcSpace.xs)
            }
        }
    }
}
