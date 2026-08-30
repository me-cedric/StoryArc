public import Foundation

/// A cover for an EPUB that declares none.
///
/// `publication-formats`: "WHEN an EPUB declares a cover image THEN that image is used;
/// otherwise the first page of the spine is rendered as the cover." Most publications
/// that declare no cover still *open* on one — a `cover.xhtml` holding a single image,
/// which is what a fixed-layout EPUB's first page is by construction and what a
/// converter emits for a reflowable one. So the first spine item is read and the image
/// it shows becomes the cover, at which point it is an ordinary path inside the
/// container and every layer above — the indexer, ``CoverLoader``, ``CoverCache`` —
/// treats it exactly like a declared one.
///
/// **What this does not do.** A first spine item that shows no image at all leaves the
/// publication without a cover, and the library draws its placeholder. Rasterising
/// arbitrary XHTML means a web view on both platforms, which is a decision
/// [ADR-0005](../../../../../docs/decisions/0005-format-and-rendering-libraries.md)
/// scoped to reading a book rather than to drawing a thumbnail of one — so the cheap
/// nine-tenths is taken and the expensive tenth is left named rather than half-built.
///
/// Split from `EpubReader.swift` because that file is at the line cap; this is the
/// cover half of the same reader.
///
/// Android's `EpubSpineCover` is the same two rules in the same order.
public enum EpubSpineCover {

    /// Every way an XHTML page can point at an image, in the order they are looked for.
    ///
    /// `src` covers `<img>`, `href` and `xlink:href` cover SVG `<image>` — which is what
    /// a fixed-layout page produced by InDesign or Calibre uses at least as often as
    /// `<img>` — and `url(...)` covers a page whose only picture is a CSS background.
    /// Nothing here parses XHTML: a cover page is one element deep and a DOM would be
    /// more code for the same answer, exactly as `EpubReader` argues for the package
    /// document.
    public static func imageReferences(in xhtml: Data) -> [String] {
        guard let text = String(data: xhtml, encoding: .utf8) else { return [] }
        var found: [String] = []
        for attribute in ["src=", "xlink:href=", "href=", "url("] {
            var rest = Substring(text)
            while let start = rest.range(of: attribute) {
                rest = rest[start.upperBound...]
                guard let value = quoted(rest) else { continue }
                if !value.isEmpty, !found.contains(value) { found.append(value) }
            }
        }
        return found
    }

    /// The value that opens where a scan has stopped: `"…"`, `'…'`, or up to `)`.
    private static func quoted(_ rest: Substring) -> String? {
        guard let opening = rest.first else { return nil }
        if opening == "\"" || opening == "'" {
            let body = rest.dropFirst()
            guard let closing = body.firstIndex(of: opening) else { return nil }
            return String(body[..<closing])
        }
        // `url(` with no quotes, which CSS allows.
        guard let closing = rest.firstIndex(of: ")") else { return nil }
        return String(rest[..<closing]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a reference names something StoryArc could decode as a cover.
    ///
    /// The extension, not the bytes: this runs against a name inside a container that
    /// has not been read yet, and reading every referenced entry to find out would cost
    /// exactly what lazy cover extraction exists to avoid.
    static func looksLikeAnImage(_ reference: String) -> Bool {
        PageOrdering.isPage(path: reference)
    }
}

extension EpubReader {
    /// The publication's cover path: the one it declares, or the image its first page
    /// shows.
    ///
    /// `nil` when neither exists, which the caller shows as a placeholder rather than
    /// as an error — a book with no cover is a book, not a failure.
    public func coverOrSpineHref() async -> String? {
        if let coverHref { return coverHref }
        guard let first = spine.first else { return nil }
        // The item's own bytes may be missing from a damaged container. That is not
        // worth an error either: it means there is no cover to be had.
        guard let xhtml = try? await data(at: first.href) else { return nil }
        let base = EpubSpineCover.directory(of: first.href)
        for reference in EpubSpineCover.imageReferences(in: xhtml) {
            guard EpubSpineCover.looksLikeAnImage(reference) else { continue }
            let resolved = EpubSpineCover.resolve(reference, against: base)
            // Only a path the container actually holds. A remote `src`, or one that
            // walked out of the container, is not a cover. `pathToEntry` is internal
            // rather than private for this one read — Swift's `private` is file-scoped,
            // and `EpubReader.swift` is at the line cap, which is why this half of the
            // reader lives here.
            if pathToEntry[resolved] != nil { return resolved }
        }
        return nil
    }
}

extension EpubSpineCover {
    /// The directory an href inside `path` resolves against.
    ///
    /// Duplicated from `EpubReader`'s own private pair rather than shared, because
    /// Swift's `private` is file-scoped and this file is the split that keeps that one
    /// under the line cap. Both are four lines and neither has ever changed.
    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// An href relative to the document that declared it, with any fragment dropped.
    static func resolve(_ href: String, against base: String) -> String {
        let withoutFragment = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        guard !withoutFragment.hasPrefix("/") else { return String(withoutFragment.dropFirst()) }
        guard !base.isEmpty else { return withoutFragment }

        var segments = base.split(separator: "/").map(String.init)
        for part in withoutFragment.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(String(part))
            }
        }
        return segments.joined(separator: "/")
    }
}
