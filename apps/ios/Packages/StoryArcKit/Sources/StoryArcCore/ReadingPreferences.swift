public import CoreGraphics

/// How pages move. See `docs/openspec/specs/comic-reader`.
public enum PageTransition: String, Sendable, Codable, CaseIterable {
    case pageCurl
    case slide
    case fade
    case verticalScroll
    case horizontalScroll

    /// Reduce Motion replaces the animated transitions with a cross-dissolve.
    /// The picker still lists them and says why — `comic-reader` forbids hiding
    /// options without an explanation.
    public var isAnimatedTransition: Bool {
        self == .pageCurl || self == .slide
    }

    public func honoring(reduceMotion: Bool) -> PageTransition {
        reduceMotion && isAnimatedTransition ? .fade : self
    }
}

public enum ReadingDirection: String, Sendable, Codable, CaseIterable {
    case leftToRight
    case rightToLeft

    /// `publication-formats`: an explicit declaration wins; otherwise Japanese
    /// with no declared direction opens right-to-left.
    public static func inferred(
        declared: ReadingDirection?,
        languageCode: String?
    ) -> ReadingDirection {
        if let declared { return declared }
        return languageCode?.lowercased().hasPrefix("ja") == true ? .rightToLeft : .leftToRight
    }
}

/// How a page is sized against the screen.
///
/// `comic-reader`: "fit-to-screen, fit-to-width, fit-to-height, and original size
/// are available, and the choice persists". The four are a *starting* scale, not a
/// replacement for zoom — a reader who pinches from fit-to-width stays zoomed until
/// they pinch back or turn the page.
public enum PageFit: String, Sendable, Codable, CaseIterable {
    /// The whole page on screen. The default, because it is the only mode that
    /// never hides part of a panel.
    case screen
    /// Full width, scrolling down. How most people read a comic on a phone: the
    /// lettering is legible and the thumb only moves one way.
    case width
    /// Full height, scrolling across. For a landscape spread on a phone held
    /// upright.
    case height
    /// One image pixel to one screen pixel, which is what a scan's own detail
    /// looks like.
    case original

    /// The scale to start at, given the page as fit-to-screen already sized it.
    ///
    /// Everything downstream measures zoom against fit-to-screen, so a mode is
    /// expressed as a multiple of it rather than as a separate layout. That is what
    /// lets pinch, double-tap and the fit control share one number.
    ///
    /// - Parameters:
    ///   - fitted: the page's size on screen at fit-to-screen.
    ///   - viewport: the space available.
    ///   - pixelWidth: the image's own width in pixels, for `original`.
    public func scale(fitted: CGSize, viewport: CGSize, pixelWidth: CGFloat) -> CGFloat {
        guard fitted.width > 0, fitted.height > 0 else { return 1 }
        return switch self {
        case .screen: 1
        case .width: max(1, viewport.width / fitted.width)
        case .height: max(1, viewport.height / fitted.height)
        // Never below fit-to-screen: a small scan shown at its own pixels would sit
        // in the middle of the screen looking like a failure to load.
        case .original: max(1, pixelWidth / fitted.width)
        }
    }
}

public enum ReaderTheme: String, Sendable, Codable, CaseIterable {
    case paper, sepia, night, contrast
}
