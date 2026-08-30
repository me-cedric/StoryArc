internal import SwiftUI

#if os(iOS)
internal import UIKit

/// The scroll view underneath ``ZoomablePage``, and the one thing it has to say that
/// `UIScrollViewDelegate` will not.
///
/// Split from `ZoomablePage.swift` when that file passed the length the linter allows.
/// The view, its representable and its coordinator stayed there; this is the small
/// subclass they rest on.

/// A scroll view that says when it has been given a size.
///
/// `UIScrollViewDelegate` reports scrolling and zooming, never layout, and layout is
/// what a page opened before its first one is waiting for: a fit set against zero
/// bounds does nothing, and no scroll and no zoom follows to prompt another try.
///
/// Only a change of size is reported. Applying a fit sets the content size and the
/// insets, which lays the view out again — a report on every pass would be a loop.
final class PageScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onLayout?(self)
    }
}
#endif
