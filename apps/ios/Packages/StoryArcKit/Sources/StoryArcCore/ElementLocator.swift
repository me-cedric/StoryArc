public import Foundation

/// Where a reflowable page starts, as text rather than as a fraction.
///
/// `reading-progress`, *Resume at the first visible element*, decision O27. A fraction names a
/// page only through the typography of the device that wrote it, so the same fraction opens
/// pages up to one page apart on iOS and Android. This names the first visible element (its
/// CSS selector) and the text just before and just after the first visible character in it.
/// A resume anchors on that text, so two devices open the same paragraph.
///
/// Android's `ElementLocator` holds the same five fields with the same names.
public struct ElementLocator: Sendable, Equatable, Codable {
    /// The resource the element is in, as the reading order names it.
    public var href: String
    public var cssSelector: String
    /// The text before the first visible character, at most ``textLimit`` characters.
    public var textBefore: String?
    /// The text from the first visible character on, at most ``textLimit`` characters.
    public var textAfter: String
    /// The content digest of the file the element was taken from.
    public var publicationDigest: String

    public init(href: String, cssSelector: String, textBefore: String?, textAfter: String, publicationDigest: String) {
        self.href = href
        self.cssSelector = cssSelector
        self.textBefore = textBefore
        self.textAfter = textAfter
        self.publicationDigest = publicationDigest
    }

    /// How much text each side keeps. Enough to find one place in a chapter, small enough
    /// for a sync document.
    public static let textLimit = 60

    /// The element a reader can store, or nil when there is nothing to anchor on.
    ///
    /// Nil without a digest, because a resume must prove the file is the same one. Nil
    /// without a selector or without visible text after the point, because the navigator
    /// can find neither.
    public static func captured(
        href: String,
        cssSelector: String?,
        textBefore: String?,
        textAfter: String?,
        publicationDigest: String?
    ) -> ElementLocator? {
        guard let cssSelector, !cssSelector.isEmpty,
              let textAfter, !textAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let publicationDigest, !publicationDigest.isEmpty
        else { return nil }
        return ElementLocator(
            href: href,
            cssSelector: cssSelector,
            textBefore: textBefore.map { String($0.suffix(textLimit)) },
            textAfter: String(textAfter.prefix(textLimit)),
            publicationDigest: publicationDigest
        )
    }

    /// Whether a resume in this publication, in this resource, goes to the element.
    ///
    /// Only the same file and the same resource. Any other case uses the fraction, because
    /// a selector in another file names another element.
    public func resumes(publicationDigest digest: String?, resource: String) -> Bool {
        digest == publicationDigest && Self.bare(href) == Self.bare(resource)
    }

    private static func bare(_ href: String) -> Substring {
        href.prefix { $0 != "#" }
    }
}
