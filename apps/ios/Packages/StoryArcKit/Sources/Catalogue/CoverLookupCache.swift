public import Foundation

public import StoryArcCore

/// What a provider answered about one publication.
///
/// A refusal is recorded as well as a hit, and that is the point of the type. `cover-art`
/// asks that "the same publication is never looked up twice, because a provider that asks
/// not to be crawled is entitled to that" — and a cache that remembers only the hits would
/// re-ask every publication a provider has no cover for, which is most of them.
public struct CoverLookupAnswer: Sendable, Equatable, Codable {
    public let provider: CoverLookupProvider

    /// Where the picture is, or nil when the provider had none.
    public let imageURL: URL?

    public init(provider: CoverLookupProvider, imageURL: URL?) {
        self.provider = provider
        self.imageURL = imageURL
    }
}

/// Every answer a provider has given, on disk, keyed by publication.
///
/// **Application Support rather than Caches.** `StorageUsage.clearCache` empties the caches
/// directory, and a reader clearing decoded pages has not asked for permission to crawl three
/// catalogues again. The file is small — one line per publication — so it costs a reader
/// nothing to keep.
public actor CoverLookupCache {
    private let file: URL
    private var answers: [String: CoverLookupAnswer]

    /// The file this reads and writes, or nil when the system has no Application Support
    /// directory to offer. A cache with nowhere to live still answers; it just forgets.
    public init(file: URL? = nil) {
        let resolved = file ?? Self.defaultFile()
        self.file = resolved ?? URL(fileURLWithPath: "/dev/null")
        answers = resolved.flatMap { url in
            try? JSONDecoder().decode(
                [String: CoverLookupAnswer].self, from: Data(contentsOf: url)
            )
        } ?? [:]
    }

    /// What this publication has already been told, or nil when it has never been asked.
    public func answer(for key: String) -> CoverLookupAnswer? {
        answers[key]
    }

    /// Records an answer, including a refusal, and writes the file.
    public func record(_ answer: CoverLookupAnswer, for key: String) {
        answers[key] = answer
        write()
    }

    /// Forgets one publication's answer, so it may be asked once more.
    ///
    /// The escape hatch a cached refusal needs. A provider that answered 429 was asking for
    /// later rather than never, and a reader who asks for this publication again by hand is
    /// the "later" — but nothing else re-asks, which is what keeps the app polite.
    public func forget(_ key: String) {
        answers.removeValue(forKey: key)
        write()
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(answers) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }

    private static func defaultFile() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("CoverLookup", isDirectory: true)
        .appendingPathComponent("answers.json")
    }
}
