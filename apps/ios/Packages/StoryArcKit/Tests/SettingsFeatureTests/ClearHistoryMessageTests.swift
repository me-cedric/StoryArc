import Testing

@testable import SettingsFeature

/// What the clear-history confirmation says about a server.
///
/// The confirmation named the files, the libraries and the settings it left untouched, and
/// said nothing about a Kavita server's own progress -- which the clear never touches
/// either, so a reader with a synchronising source had every reason to read the silence as
/// "everywhere". Android mirrors this in `ClearHistoryMessageTest`.
@Suite("The clear-history confirmation names a server")
struct ClearHistoryMessageTests {

    @Test("With no synchronising source, only the body is shown")
    func noSynchronizingSource() {
        #expect(
            PrivacySettings.clearHistoryMessageKeys(hasSynchronizingSource: false)
                == ["privacy.clear.history.body"]
        )
    }

    @Test("With one, the server sentence follows the body")
    func withASynchronizingSource() {
        #expect(
            PrivacySettings.clearHistoryMessageKeys(hasSynchronizingSource: true)
                == ["privacy.clear.history.body", "privacy.clear.history.serverNote"]
        )
    }
}
