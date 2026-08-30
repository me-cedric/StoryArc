import Foundation
import Testing

@testable import SettingsFeature

/// What a problem report arrives pre-filled with.
///
/// `settings-and-about`: the issue tracker opens "with the app version, platform version,
/// and device class pre-filled, and no personal data". Three facts, and Android carried two
/// of them — which is what these assertions are here to keep from happening again on either
/// side.
///
/// Mirrored case for case by `ProblemReportTest.kt`.
@Suite("Problem report")
struct ProblemReportTests {

    @Test("a report carries the version, the platform and the device class, in that order")
    func carriesTheThreeFacts() {
        let body = BuildInfo.issueBody(platform: "iOS 26.0", deviceClass: "iPad")
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { !$0.isEmpty }
        #expect(lines.count == 3)
        #expect(lines.first?.hasPrefix("StoryArc ") == true)
        #expect(lines.dropFirst().first == "iOS 26.0")
        #expect(lines.last == "iPad")
    }

    @Test("a report carries nothing else")
    func carriesNothingElse() {
        // No reader-typed text, no source name, no file path, no account. Everything in
        // the body arrives from the two arguments and the build's own version.
        let body = BuildInfo.issueBody(platform: "iOS 26.0", deviceClass: "iPhone")
        #expect(body.hasSuffix("\n\n"))
        #expect(body.split(separator: "\n").count == 3)
    }
}
