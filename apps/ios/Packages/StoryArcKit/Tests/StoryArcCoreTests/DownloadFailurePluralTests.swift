import Foundation
import Testing

/// The failure line under a download counts its attempts, in each of the four languages.
///
/// `offline-downloads` caps a download at three attempts, so **one attempt is the first
/// thing a reader sees when a download fails** — and the line read "Failed after 1
/// attempts". Android draws the same sentence through `R.plurals.downloads_failed` and has
/// read "1 attempt" since it was written, so this was a mirror defect: one platform right,
/// the other wrong.
///
/// **The catalogue is compiled, not parsed.** `swift test` does not process an
/// `.xcstrings`, so `String(localized:)` answers with the key on the host — which is why
/// every other suite here asserts keys rather than sentences. A plural cannot be asserted
/// that way: the whole question is which of several values the platform picks for a given
/// count, and only the compiled catalogue answers it. So this suite runs the same
/// `xcstringstool compile` the app target runs, opens the produced `<language>.lproj` as a
/// bundle, and renders the sentence the reader would see.
///
/// It is the app target's catalogue rather than this package's, reached by path. That is
/// unusual and deliberate: the line is drawn by `apps/ios/App/DownloadQueueSection.swift`,
/// the app target has no unit tests of its own, and a sentence nothing renders is a
/// sentence nothing checks.
@Suite("The download failure line counts its attempts")
struct DownloadFailurePluralTests {

    /// The key `Text("downloads.failed \(reason) \(attempts)")` derives: reason, then count.
    private static let key = "downloads.failed %@ %lld"

    /// A reason with no digit in it, so a rendered count is the only number in the sentence.
    private static let reason = "Offline"

    private enum Failure: Error {
        case toolFailed(String)
        case noBundle(String)
    }

    @Test(
        "A first failure says one attempt rather than one attempts",
        arguments: ["en", "fr", "de", "es"]
    )
    func aSingleAttemptIsSingular(_ language: String) throws {
        let format = try Self.compiledFormat(for: language)
        let locale = Locale(identifier: language)
        let one = String(format: format, locale: locale, Self.reason as NSString, 1)
        let two = String(format: format, locale: locale, Self.reason as NSString, 2)

        // Language-agnostic, and it states the defect exactly. A catalogue with no plural
        // renders one sentence for every count, so writing "1" where the two-attempt
        // sentence writes "2" reproduces it character for character. A catalogue with a
        // plural cannot: the singular differs by more than its digit.
        #expect(
            one != two.replacingOccurrences(of: "2", with: "1"),
            "\(language) has no plural: one attempt renders as \"\(one)\""
        )
    }

    @Test("The English sentence reads both ways, as its Android twin does")
    func englishReadsBothWays() throws {
        let format = try Self.compiledFormat(for: "en")
        let locale = Locale(identifier: "en")

        #expect(
            String(format: format, locale: locale, Self.reason as NSString, 1)
                == "Failed after 1 attempt: Offline",
            "the English singular is not the sentence Android draws"
        )
        #expect(
            String(format: format, locale: locale, Self.reason as NSString, 3)
                == "Failed after 3 attempts: Offline",
            "the English plural is not the sentence Android draws"
        )
    }

    /// The format string one language resolves to, out of the compiled app catalogue.
    ///
    /// A fresh directory per call, removed before returning: `Bundle(url:)` caches by path,
    /// so two calls sharing one path would share one answer.
    private static func compiledFormat(for language: String) throws -> String {
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "storyarc-strings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }

        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        tool.arguments = [
            "xcstringstool", "compile",
            "--output-directory", output.path(),
            catalogue.path(),
        ]
        let errors = Pipe()
        tool.standardError = errors
        try tool.run()
        let complaint = errors.fileHandleForReading.readDataToEndOfFile()
        tool.waitUntilExit()
        guard tool.terminationStatus == 0 else {
            throw Failure.toolFailed(String(bytes: complaint, encoding: .utf8) ?? "")
        }

        guard let bundle = Bundle(url: output.appending(path: "\(language).lproj")) else {
            throw Failure.noBundle(language)
        }
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    /// The app target's catalogue, from this file rather than from a working directory.
    private static var catalogue: URL {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory = directory.deletingLastPathComponent() }
        return directory.appending(path: "App/Resources/Localizable.xcstrings")
    }
}
