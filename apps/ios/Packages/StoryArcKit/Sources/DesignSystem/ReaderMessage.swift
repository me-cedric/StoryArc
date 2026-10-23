public import SwiftUI

/// A word over the reader's matte: a mark, then one footnote line under it.
///
/// The comic reader says a failure, a wait and an undecodable page with it; the EPUB reader
/// says a failure. The colour and the padding stay with the caller: the comic reader draws
/// on a black matte and the EPUB reader on the theme's canvas.
public struct ReaderMessage: View {
    public enum Mark {
        /// A warning glyph: something did not open or did not decode.
        case warning
        /// A spinner: the reader waits, and nothing is wrong.
        case waiting
    }

    private let mark: Mark
    private let text: Text

    public init(_ mark: Mark, _ text: Text) {
        self.mark = mark
        self.text = text
    }

    public var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            switch mark {
            case .warning:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .light))
            case .waiting:
                ProgressView()
            }
            text
                .textRole(.footnote)
                .multilineTextAlignment(.center)
        }
    }
}
