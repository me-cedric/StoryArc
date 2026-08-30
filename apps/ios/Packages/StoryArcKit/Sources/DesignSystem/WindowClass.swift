public import CoreGraphics

/// How much room the window has, and therefore which navigation it asks for.
///
/// `native-experience` says two things that have to be answered together: a large screen
/// "uses a multi-column layout with a persistent sidebar, not a stretched phone layout",
/// and a window that is resized "reflows continuously". The first alone would be
/// satisfied by asking what device this is; the second is what makes that answer wrong.
/// An iPad in a third of the screen is still an iPad and has a phone's worth of width,
/// and a foldable is a phone that becomes a tablet in the reader's hands.
///
/// So the only input here is the width of the window, and there is no device check
/// anywhere. Split View, Slide Over, Stage Manager, a rotation, a fold and an Android
/// multi-window drag are all the same event: the number changed.
///
/// 600 is Material 3's medium breakpoint and roughly where iOS's own `.regular`
/// horizontal size class begins, so both apps change shape in the same place. Android's
/// `StoryArcWindowClass` holds the same two cases and the same number in density-
/// independent pixels.
public enum StoryArcWindowClass: Sendable, Hashable, CaseIterable {
    /// A phone, an iPad in a narrow Split View slot, a Slide Over panel, a folded
    /// foldable. One column, with everything else behind chrome.
    case compact
    /// Room for a sidebar beside the content.
    case expanded

    /// The width, in points, at or above which a sidebar fits beside a grid of covers
    /// without either of them becoming unreadable.
    public static let sidebarWidthThreshold: CGFloat = 600

    /// Which class a window of this width is.
    ///
    /// A width of zero is what a view reports before it has been laid out, and it
    /// resolves to `compact`: the single-column layout fits every window and the wide
    /// one does not, so the narrow answer is the safe one to be wrong with for a frame.
    public static func of(width: CGFloat) -> Self {
        width >= sidebarWidthThreshold ? .expanded : .compact
    }

    /// Whether this window gets the platform's split navigation rather than a stack.
    public var showsSidebar: Bool { self == .expanded }
}
