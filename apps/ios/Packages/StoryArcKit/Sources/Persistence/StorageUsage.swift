public import Foundation

internal import WebKit

/// What StoryArc is using on disk, and how to give it back.
///
/// `settings-and-about` asks for cache, reading history and downloads to be "individually
/// clearable, each stating what it removes and how much space it frees". A number is the
/// point: "clear cache" with no size behind it asks a reader to guess whether it is worth
/// doing.
///
/// Downloads are not measured here. They are, but by whoever owns them: ``DownloadStore``
/// walks its own directory and the size is handed to the Privacy screen, because this type
/// knows about the cache and the history and has no business knowing where a download lands.
public struct StorageUsage: Sendable {

    /// The directory this measures and empties. The system's, unless a test says otherwise.
    private let caches: URL?

    /// The other half of what the row promises: the web view's cookies and origin storage.
    ///
    /// Injected so a test can watch it happen. The real one talks to `WKWebsiteDataStore`,
    /// which is a process-wide singleton — a test that called it would be clearing the test
    /// host's own website storage, which is not a decision a test gets to make.
    private let removeWebsiteData: @Sendable @MainActor () async -> Void

    public init(
        caches: URL? = nil,
        removeWebsiteData: @escaping @Sendable @MainActor () async -> Void
            = StorageUsage.removeAllWebsiteData
    ) {
        self.caches = caches
        self.removeWebsiteData = removeWebsiteData
    }

    /// Bytes the caches directory is holding. Includes the web view's own.
    public func cacheBytes() -> Int64 {
        guard let caches = cachesDirectory else { return 0 }
        return Self.size(of: caches)
    }

    /// Empties the caches directory, and the web view's cookies and origin storage with it.
    ///
    /// Contents rather than the directory itself: removing the directory out from under a
    /// web view that has it open is how the next page load finds nothing where it expected a
    /// writable path.
    ///
    /// The second half is what the row has always said and never did. "Decoded pages and
    /// web-view data" is the string on the Privacy screen in all four languages; the web
    /// view's *cache* does live in this directory, but its cookies and per-origin storage do
    /// not — so a publication that reached the network could leave an identifier behind that
    /// the reader had just been told was gone. Clearing them is the honest half of that
    /// choice, and cheaper than translating a smaller promise four times.
    ///
    /// Android's `StorageUsage.clearCache` clears `CookieManager` and `WebStorage` in the
    /// same call, for the same reason.
    public func clearCache() async {
        if let caches = cachesDirectory {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: caches, includingPropertiesForKeys: nil
            )) ?? []
            for item in contents {
                try? FileManager.default.removeItem(at: item)
            }
        }
        await removeWebsiteData()
    }

    /// Every kind of website data WebKit knows about, since the reader asked for all of it.
    ///
    /// `.distantPast` rather than a recent window: "clear" means clear.
    @MainActor
    public static func removeAllWebsiteData() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    private var cachesDirectory: URL? {
        caches ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private static func size(of directory: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}

/// A size a person can read, in their own locale.
///
/// Powers of 1024 with the SI names, which is what every file manager on both platforms
/// shows — matching the convention a reader already has beats being right about kibibytes.
///
/// The number is formatted through `Locale.current`, not by `String(format:)`. That
/// composes a fixed decimal point, so a French reader saw "1.4 MB" where every other app
/// on their phone says "1,4 Mo". `localization` requires "numbers, dates and file sizes"
/// to follow the locale, and a hand-composed float does not.
public func formattedBytes(_ bytes: Int64) -> String {
    switch bytes {
    case ..<1: "0 kB"
    case ..<1024: "1 kB"
    case ..<(1024 * 1024): "\(bytes / 1024) kB"
    case ..<(1024 * 1024 * 1024): scaled(bytes, by: 1024 * 1024, unit: "MB")
    default: scaled(bytes, by: 1024 * 1024 * 1024, unit: "GB")
    }
}

/// One decimal place, in the reader's own number format.
private func scaled(_ bytes: Int64, by divisor: Double, unit: String) -> String {
    let value = (Double(bytes) / divisor).formatted(
        .number.precision(.fractionLength(1)).locale(.current)
    )
    return "\(value) \(unit)"
}
