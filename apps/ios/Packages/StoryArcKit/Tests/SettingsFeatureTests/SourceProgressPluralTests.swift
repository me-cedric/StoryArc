import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature
import StoryArcCore

/// Task 25.6: "1 of 1 titles". The progress sentence takes its noun from the total, as
/// Android's `sources_detail_progress` plural does.
///
/// `@MainActor` and `.serialized` because the chosen language is one value for the process.
@MainActor
@Suite("Source progress plural", .serialized)
struct SourceProgressPluralTests {

    private func progress(_ read: Int, of total: Int) -> String {
        String(describing: sourceProgressText(read: read, total: total))
    }

    @Test("A total of one reads the singular noun")
    func totalOfOneIsSingular() {
        #expect(progress(1, of: 1).contains("\"1 of 1 title\""), "read: \(progress(1, of: 1))")
        #expect(progress(0, of: 1).contains("\"0 of 1 title\""), "read: \(progress(0, of: 1))")
    }

    @Test("A total of several reads the plural noun")
    func totalOfSeveralIsPlural() {
        #expect(progress(2, of: 3).contains("\"2 of 3 titles\""), "read: \(progress(2, of: 3))")
        #expect(progress(1_200, of: 5_000).contains(" titles\""))
    }

    @Test("French takes its singular from the total too")
    func frenchSingular() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        #expect(progress(1, of: 1).contains("\"1 sur 1 titre\""), "read: \(progress(1, of: 1))")
        #expect(progress(1, of: 2).contains("\"1 sur 2 titres\""), "read: \(progress(1, of: 2))")
    }
}
