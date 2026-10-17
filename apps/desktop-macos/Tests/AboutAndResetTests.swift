import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// `settings-and-about`, *About*: the version, the byline as the one way to the author, the
/// repository and the licence, the support link stated once, every third-party library in
/// the Mac build with its licence text, and a problem report pre-filled with no personal data.
@Suite("About")
struct AboutTests {
    @Test("The byline is the only row to the author's address, and the other links are the spec's")
    func links() {
        let rows = MacAbout.links
        #expect(MacAbout.author == URL(string: "https://github.com/me-cedric"))
        #expect(!rows.contains(MacAbout.author), "a second row opens the author's address")
        #expect(rows.contains(URL(string: "https://github.com/me-cedric/StoryArc")))
        #expect(rows.contains(URL(string: "https://ko-fi.com/mecedric")))
        #expect(rows.contains(URL(string: "https://github.com/me-cedric/StoryArc/blob/main/LICENSE")))
    }

    @Test("A problem report opens the tracker with the version, the system and the device class, nothing else")
    func report() throws {
        let url = try #require(MacAbout.issue(version: "0.1.0", build: "7", system: "macOS 27.0.1"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "github.com")
        #expect(components.path == "/me-cedric/StoryArc/issues/new")
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(body == "StoryArc 0.1.0 (7)\nmacOS 27.0.1\nMac\n\n")
        #expect(components.queryItems?.count == 1)
        #expect(!body.contains(NSUserName()), "the report carries the account name")
    }

    @Test("Every library the Mac build carries is acknowledged with its licence text")
    func acknowledgements() throws {
        let notices = try MacAbout.notices()
        #expect(notices.map(\.name).sorted() == MacAbout.linked.sorted())
        for notice in notices {
            #expect(MacAbout.licenceText(for: notice)?.isEmpty == false, "\(notice.name) has no licence text")
        }
    }

    @Test("The version and build are read from the app, not written down")
    func version() {
        #expect(MacAbout.version == Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        #expect(MacAbout.build == Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
    }
}

/// `settings-and-about`, *Resetting*: the preferences go back to their defaults, and the
/// folders, downloads and reading progress are not touched.
@MainActor
@Suite("Settings reset")
struct SettingsResetTests {
    @Test("A reset puts every preference back and leaves the folders and the history alone")
    func resetKeepsWhatItSays() throws {
        let scratch = try ScratchDefaults(prefix: "mac-reset-")
        defer { scratch.remove() }
        let defaults = scratch.defaults
        let folders = Data([1, 2, 3])
        defaults.set(folders, forKey: MacFolderBookmarks.defaultKey)
        defaults.set(["/comics/a.cbz"], forKey: RecentPublications.defaultsKey)
        let settings = MacSettings(defaults: defaults)
        settings.accent = .system
        settings.textSize = .largest
        settings.coverAlone = false
        settings.settings.turnPagesByTappingTheEdges = false
        settings.settings.appearance = .dark

        settings.reset()

        #expect(settings.accent == .brand)
        #expect(settings.textSize == .default)
        #expect(settings.coverAlone)
        #expect(settings.settings == AppSettings.defaults)
        let reread = MacSettings(defaults: defaults)
        #expect(reread.accent == .brand && reread.textSize == .default && reread.settings == AppSettings.defaults)
        #expect(defaults.data(forKey: MacFolderBookmarks.defaultKey) == folders)
        #expect(defaults.stringArray(forKey: RecentPublications.defaultsKey) == ["/comics/a.cbz"])
    }

    @Test("Search finds the reset and the About tab")
    func searchable() {
        #expect(SettingsIndex.matches("reset").map(\.id).contains("reset"))
        #expect(SettingsIndex.matches("licence").map(\.id).contains("about"))
        #expect(SettingsTab.allCases.last == .about)
    }
}
