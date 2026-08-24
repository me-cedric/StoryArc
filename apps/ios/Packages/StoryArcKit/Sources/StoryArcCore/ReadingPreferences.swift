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

public enum PageFit: String, Sendable, Codable, CaseIterable {
    case screen, width, height, original
}

public enum ReaderTheme: String, Sendable, Codable, CaseIterable {
    case paper, sepia, night, contrast
}
