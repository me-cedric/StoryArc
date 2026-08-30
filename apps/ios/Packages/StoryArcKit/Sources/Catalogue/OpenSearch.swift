public import Foundation

/// An OpenSearch description document, reduced to the one thing a catalogue search needs.
///
/// `opds-catalog`: "when a catalogue advertises an OpenSearch description, searching within
/// that source queries the server rather than filtering locally". Most OPDS 1.2 servers
/// advertise it this way — a `rel="search"` link pointing at a small XML document — rather
/// than putting the template inline in the href, which is what OPDS 2.0 does. The feed
/// parser records where the document is; this reads it.
///
/// Android's `OpenSearchDescription` is the same reader, asserted against the same cases.
public enum OpenSearchDescription {

    /// The query template this document offers, resolved against where the document lives.
    ///
    /// `nil` when the body is not a description document, offers no `Url` with a template,
    /// or offers only templates for formats a reader cannot browse here. A caller that gets
    /// `nil` has a catalogue with no usable search, which is the fallback the spec names.
    public static func template(_ data: Data, baseURL: URL) -> String? {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { return nil }
        guard let chosen = choose(reader.urls) else { return nil }
        return OpdsDocument.resolveTemplate(chosen.template, relativeTo: baseURL)
    }

    /// One `<Url>` of a description document.
    struct Offer: Equatable {
        let type: String
        let template: String
    }

    /// Which of the offered templates a catalogue browser should use.
    ///
    /// A description document commonly offers several: one that answers with a feed, one
    /// that answers with a web page, sometimes one that answers with suggestions. Only the
    /// first is any use here, and a browser that took the HTML one would put the reader's
    /// query to a page it cannot render.
    ///
    /// Internal rather than private so the choice can be asserted on its own, the way
    /// Android asserts it.
    static func choose(_ offers: [Offer]) -> Offer? {
        let usable = offers.filter { !$0.template.isEmpty }
        return usable.first { $0.type.lowercased().contains("opds") }
            ?? usable.first { $0.type.lowercased().contains("atom") }
            // A document that declares no type at all is still a document. Preferred over
            // a type that names something this app cannot read.
            ?? usable.first { $0.type.isEmpty }
            ?? usable.first { !$0.type.lowercased().contains("html") }
    }

    /// Collects every `<Url>` the document declares.
    private final class Reader: NSObject, XMLParserDelegate {
        private(set) var urls: [Offer] = []

        func parser(
            _ parser: XMLParser,
            didStartElement element: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            guard element == "Url" else { return }
            urls.append(
                Offer(
                    type: attributes["type"] ?? "",
                    template: attributes["template"] ?? ""
                )
            )
        }
    }
}
