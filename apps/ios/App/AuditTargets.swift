import SwiftUI

extension View {
    /// Two buttons that exist for one UI test, in a debug build, when it asks for them.
    ///
    /// `AccessibilityAuditTests` is only worth its green if it can go red. The audit checks hit
    /// regions, and no screen of this app has a control under 44 points on purpose, so the test
    /// could not tell an audit that measures from an audit that measures nothing. The launch
    /// argument below draws one button of 30 points and one of 44, and
    /// `CatalogueAuditTests.testAThirtyPointTargetFails` asks the audit about both.
    ///
    /// A release build has no such code: the body is `self`.
    @ViewBuilder
    func auditTargets() -> some View {
        #if DEBUG
        overlay(alignment: .bottomLeading) { AuditTargets() }
        #else
        self
        #endif
    }
}

#if DEBUG
private struct AuditTargets: View {
    /// Read once. A launch argument cannot change while the process runs.
    private static let isRequested = ProcessInfo.processInfo.arguments.contains("-storyarc.audit.targets")

    var body: some View {
        if Self.isRequested {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([18, 24, 30, 36, 40, 44], id: \.self) { size in
                    target(size: CGFloat(size), identifier: "audit.target.\(size)")
                }
            }
            .padding(.leading, 24)
            .padding(.bottom, 160)
        }
    }

    private func target(size: CGFloat, identifier: String) -> some View {
        Button {} label: {
            Image(systemName: "star.fill")
                .frame(width: size, height: size)
                .background(.tint, in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
#endif
