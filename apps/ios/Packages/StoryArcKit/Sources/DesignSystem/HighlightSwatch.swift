public import SwiftUI

public import StoryArcCore

public extension HighlightColour {
    /// What the colour looks like on a page.
    ///
    /// Fixed hues rather than palette tokens: a highlight is ink a reader chose, and one that
    /// changed colour when they changed theme would stop meaning what they meant by it. The
    /// opacity a renderer composites this at is what keeps the words legible under it — a
    /// solid fill would bury the thing being marked.
    ///
    /// Here rather than in a reader, because both readers draw it. The EPUB navigator
    /// composites it over reflowed text and the PDF reader paints it over a rasterised page,
    /// and a highlight that was two different yellows depending on the format would be a
    /// defect one reader could see in one library.
    var swatch: SwiftUI.Color {
        switch self {
        case .yellow: SwiftUI.Color(red: 1.00, green: 0.85, blue: 0.25)
        case .green: SwiftUI.Color(red: 0.45, green: 0.85, blue: 0.45)
        case .blue: SwiftUI.Color(red: 0.40, green: 0.72, blue: 1.00)
        case .pink: SwiftUI.Color(red: 1.00, green: 0.55, blue: 0.75)
        case .purple: SwiftUI.Color(red: 0.72, green: 0.55, blue: 1.00)
        }
    }
}
