public import Foundation

/// What StoryArc is using on disk, and how to give it back.
///
/// `settings-and-about` asks for cache, reading history and downloads to be "individually
/// clearable, each stating what it removes and how much space it frees". A number is the
/// point: "clear cache" with no size behind it asks a reader to guess whether it is worth
/// doing.
///
/// Downloads are absent because `offline-downloads` is not built. That is said on the screen
/// rather than shown as a zero, which would imply there is a thing here that happens to be
/// empty.
public struct StorageUsage: Sendable {
    public init() {}

    /// Bytes the caches directory is holding. Includes the web view's own.
    public func cacheBytes() -> Int64 {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return 0 }
        return Self.size(of: caches)
    }

    /// Empties the caches directory.
    ///
    /// Contents rather than the directory itself: removing the directory out from under a
    /// web view that has it open is how the next page load finds nothing where it expected a
    /// writable path.
    public func clearCache() {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: caches, includingPropertiesForKeys: nil
        )) ?? []
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
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
