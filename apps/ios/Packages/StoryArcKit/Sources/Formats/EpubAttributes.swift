import Foundation

// XML attribute lookup, split out of `EpubReader`.
//
// A package document's attributes are matched case-insensitively and sometimes
// namespaced, which is a rule about XML rather than about EPUB — it belongs
// beside the reader, not inside it.

extension [String: String] {
    /// An element's text content, trimmed. Stored under a key no attribute can use.
    var text: String? {
        guard let raw = self["#text"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return raw
    }
}
