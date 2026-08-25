internal import SwiftUI

internal import StoryArcCore

/// How the fit modes are named on screen.
///
/// The enum lives in the domain and carries no strings: `StoryArcCore` has no
/// bundle and no business holding UI copy. Short labels, because four of them share
/// the width of a phone.
extension PageFit {
    var shortTitleKey: LocalizedStringKey {
        switch self {
        case .screen: "reader.fit.screen"
        case .width: "reader.fit.width"
        case .height: "reader.fit.height"
        case .original: "reader.fit.original"
        }
    }
}
