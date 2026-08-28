internal import Foundation

/// Series, volume, issue and year guessed from a filename.
///
/// `publication-formats` requires this when a publication carries no embedded
/// metadata, and requires the results to be **marked as inferred**: a later
/// authoritative source — a Kavita server, an OPDS catalogue, a `ComicInfo.xml`
/// added afterwards — must be able to replace a guess without asking the user to
/// resolve a conflict it invented.
///
/// So `isInferred` is always true here. The flag exists on the type rather than
/// at the call site because it travels with the values, and a guess that loses
/// its label becomes indistinguishable from a fact.
public struct FilenameMetadata: Sendable, Equatable {
    public let series: String?
    /// Issue or chapter. A string for the same reason `ComicInfo.number` is one:
    /// "3.5" is a real issue number.
    public let number: String?
    public let volume: Int?
    public let year: Int?

    /// Always true. Every value here is a guess, and the point is that it says so.
    public let isInferred = true

    /// Reads what a filename implies. The extension is ignored, and a name that
    /// implies nothing yields a series and nothing else.
    ///
    /// ponytail: an ordered set of patterns over one string, not a grammar. Comic
    /// filenames have no syntax to parse — they have conventions, and the honest
    /// model of a convention is a list of shapes tried in order. The cases the
    /// list must handle live in the shared corpus manifest, so both platforms
    /// agree on what "common naming pattern" means.
    /// - Parameter seriesHint: what the containing folder is called, used only
    ///   when the filename yields no series of its own.
    public init(filename: String, seriesHint: String? = nil, catalogued: String? = nil) {
        // A dotfile is not a publication, and `deletingPathExtension` leaves
        // ".cbz" intact — which would otherwise be read as a series called "cbz".
        guard !filename.hasPrefix(".") else {
            self.series = nil
            self.number = nil
            self.volume = nil
            self.year = nil
            return
        }
        var stem = (filename as NSString).deletingPathExtension as String

        // Bracketed groups — scanlation credits, quality tags, language tags —
        // are never part of a title, and leaving them in makes every file from
        // one group look like a different series.
        stem = Self.removingBracketed(stem)

        // The year first, and only from parentheses. A bare four-digit number is
        // ambiguous: "Blame! 2001" is a title. Parentheses are what make it a
        // claim about a date.
        var year: Int?
        if let match = Self.lastParenthesised(in: stem, matching: Self.isYear) {
            year = Int(match.value)
            stem = stem.replacingOccurrences(of: match.whole, with: " ")
        }

        // Volume, before the issue number: `v02` and `Vol. 3` would otherwise be
        // read as issues.
        var volume: Int?
        for pattern in ["\\bv(?:ol)?\\.?\\s*(\\d{1,4})\\b"] {
            if let match = Self.firstMatch(pattern, in: stem, group: 1) {
                volume = Int(match.value)
                stem = stem.replacingOccurrences(of: match.whole, with: " ")
                break
            }
        }
        // `(v104)`, a manga convention the parenthesis pass above leaves behind
        // because it is not a year.
        if volume == nil, let match = Self.firstMatch("\\(v(\\d{1,4})\\)", in: stem, group: 1) {
            volume = Int(match.value)
            stem = stem.replacingOccurrences(of: match.whole, with: " ")
        }

        // The issue or chapter, most explicit marker first. A trailing bare number
        // is last, because it is the weakest signal and the one that misreads a
        // title.
        var number: String?
        for pattern in [
            "#\\s*(\\d{1,5}(?:\\.\\d+)?)",             // #011
            "\\bc(?:h(?:apter)?)?\\.?\\s*(\\d{1,5}(?:\\.\\d+)?)\\b",  // c1044, ch. 12, Chapter 364
            // A trailing bare number, capped at three digits. Four is where a
            // number stops looking like an issue and starts looking like part of
            // the title: "Blame! 2001" is a series, not issue 2001 of "Blame!".
            //
            // ponytail: the ceiling is that a four-digit chapter needs an explicit
            // marker — "c1044", not "1044". Every naming convention that goes that
            // high uses one, so the guess stays on the safe side of a title.
            // `(?:^|\s)` rather than `\s`, so a name that is *only* a number —
            // "003.cbz", the usual shape inside a per-series folder — reads as
            // issue three with no series, leaving the folder to supply one.
            "(?:^|\\s)(\\d{1,3}(?:\\.\\d+)?)\\s*$",
        ] {
            if let match = Self.firstMatch(pattern, in: stem, group: 1) {
                number = Self.trimmingLeadingZeros(match.value)
                stem = stem.replacingOccurrences(of: match.whole, with: " ")
                break
            }
        }

        self.year = year
        self.volume = volume
        self.number = number
        // The catalogue first, when there is one: a server that keeps the library knows
        // the series, and a downloaded or cached file is often named after an identifier
        // rather than after itself. Then the filename, because a folder name describes a
        // shelf and a filename describes the book on it.
        self.series = catalogued ?? Self.tidySeries(stem) ?? seriesHint
    }

    // MARK: - Private

    private struct Match {
        /// The whole matched text, so it can be removed from the string.
        let whole: String
        /// The captured group.
        let value: String
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)
              ),
              let wholeRange = Range(match.range, in: text),
              let groupRange = Range(match.range(at: group), in: text)
        else { return nil }
        return Match(whole: String(text[wholeRange]), value: String(text[groupRange]))
    }

    /// The last parenthesised group satisfying a test.
    ///
    /// Last rather than first: a title may contain parentheses of its own, and the
    /// publication year conventionally comes after the title.
    private static func lastParenthesised(
        in text: String, matching test: (String) -> Bool
    ) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: "\\((\\d{4})\\)") else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range, in: text),
                  let groupRange = Range(match.range(at: 1), in: text)
            else { continue }
            let value = String(text[groupRange])
            if test(value) {
                return Match(whole: String(text[wholeRange]), value: value)
            }
        }
        return nil
    }

    /// A plausible publication year. Comics predate 1900 nowhere, and a
    /// four-digit number past next year is something else.
    private static func isYear(_ value: String) -> Bool {
        guard let number = Int(value) else { return false }
        return number >= 1900 && number <= 2200
    }

    private static func removingBracketed(_ text: String) -> String {
        var out = text
        for pattern in ["\\[[^\\]]*\\]", "\\{[^}]*\\}"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            out = regex.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: " "
            )
        }
        return out
    }

    private static func trimmingLeadingZeros(_ value: String) -> String {
        // "#01" and "#1" are the same issue, and a library that sorts them apart
        // looks broken. A value that is all zeros stays "0".
        let trimmed = value.drop(while: { $0 == "0" })
        return trimmed.isEmpty || trimmed.hasPrefix(".") ? value.hasPrefix("0") ? "0" : value
            : String(trimmed)
    }

    /// What is left after the markers are removed, as a title.
    private static func tidySeries(_ text: String) -> String? {
        var out = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        // Separators left dangling by a removed marker: "One Piece - " and
        // "Invincible #" should both come back as the title alone.
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: " -–—_#.,:;()"))
        return out.isEmpty ? nil : out
    }
}
