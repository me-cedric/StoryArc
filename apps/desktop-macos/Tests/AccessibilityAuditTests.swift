import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// `native-experience`, *Guidelines are checked by machine*, on every screen of the Mac's
    /// catalogue at the default and the largest text size: each control a reader acts on
    /// carries a name and is at least 20 by 20 points.
    @MainActor
    @Suite("Accessibility audit")
    struct AccessibilityAuditTests {
        @Test("Every control on every catalogue screen is named and at least the macOS floor")
        func catalogue() async throws {
            let (library, reading) = try await MacCatalogue.prepare()
            defer { MacSettings.shared.textSize = .default }
            var findings: [AccessibilityAudit.Finding] = []
            var empty: [String] = []
            for size in [ChromeTextSize.default, .largest] {
                MacSettings.shared.textSize = size
                try await MacCatalogue.walk(library: library, reading: reading) { screen, window in
                    let name = size == .default ? screen : "\(screen) (largest)"
                    if AccessibilityAudit.controls(in: window).isEmpty, !MacCatalogue.chromeless.contains(screen) {
                        empty.append(name)
                    }
                    findings += AccessibilityAudit.findings(in: window, screen: name)
                }
            }
            #expect(empty.isEmpty, "the audit read no control on \(empty)")
            let listed = findings.map(\.description).joined(separator: "\n")
            #expect(findings.isEmpty, "\(findings.count) findings:\n\(listed)")
        }

        @Test("The audit names a control under the floor and one with no name")
        func auditCatchesDefects() {
            func button(_ name: String, _ side: CGFloat) -> AccessibilityAudit.Control {
                let size = CGSize(width: side, height: side)
                return AccessibilityAudit.Control(role: "AXButton", subrole: "", name: name, size: size)
            }
            let small = button("Close", 9)
            let unnamed = button("", 28)
            let fine = button("Open", 20)
            #expect(small.isTooSmall && !small.isUnnamed)
            #expect(unnamed.isUnnamed && !unnamed.isTooSmall)
            #expect(!fine.isTooSmall && !fine.isUnnamed)
        }
    }
}
