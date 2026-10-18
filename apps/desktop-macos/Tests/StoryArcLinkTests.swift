import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// The `storyarc://` link and the command line, task 5.8: a plain link opens, an unknown
/// title is named and changes nothing, a link carrying a command is refused, as the Windows
/// `StoryArcLinkTests` hold for the same three scenarios of `desktop-experience`.
@Suite("StoryArc link")
struct StoryArcLinkTests {
    static let saga = Publication(
        identity: PublicationIdentity(normalizedPath: "/comics/Saga 1.cbz"), format: .cbz, displayTitle: "Saga 1",
        origin: .inferred, addedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    static let strip = Publication(
        identity: PublicationIdentity(normalizedPath: "/comics/Strip.cbt"), format: .cbt, displayTitle: "Strip",
        origin: .inferred, addedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    static let comics = Source(displayName: "Comics", kind: .localFolder, locator: "/comics")

    private func resolve(_ link: String) throws -> StoryArcLink.Action {
        let url = try #require(URL(string: link))
        return StoryArcLink.resolve(url, publications: [Self.saga, Self.strip], sources: [Self.comics])
    }

    @Test("A plain link to a title the library holds opens it, by title or by id")
    func opensByTitle() throws {
        #expect(try resolve("storyarc://publication/Saga%201") == .open(Self.saga))
        #expect(try resolve("storyarc://publication/saga%201") == .open(Self.saga))
        let id = Self.strip.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let byID = "storyarc://publication/" + id
        #expect(try resolve(byID) == .open(Self.strip))
    }

    @Test("A link to a source shows the sources")
    func showsSource() throws {
        #expect(try resolve("storyarc://source/Comics") == .showSource(Self.comics))
    }

    @Test("An unknown title or source is named and nothing opens", arguments: [
        ("storyarc://publication/Nothing%20Like%20It", "Nothing Like It"),
        ("storyarc://source/Elsewhere", "Elsewhere"),
    ])
    func unknownIsNamed(link: String, name: String) throws {
        #expect(try resolve(link) == .notFound(name))
    }

    @Test("A link carrying a command or naming nothing is refused", arguments: [
        "storyarc://settings/reset", "storyarc://clear-history", "storyarc://publication",
        "storyarc://publication/Saga%201/delete", "storyarc://run/Terminal.app", "storyarc:",
        "https://publication/Saga%201",
    ])
    func commandIsRefused(link: String) throws {
        #expect(try resolve(link) == .refused)
    }

    @Test("A query after a name is ignored and only the name opens")
    func queryIgnored() throws {
        #expect(try resolve("storyarc://publication/Strip?delete=all&exec=calc#now") == .open(Self.strip))
    }

    @Test("A link is told from a path", arguments: [
        ("storyarc://publication/Saga%201", true), ("STORYARC://x", true), ("/comics/Saga 1.cbz", false),
        ("-NSDocumentRevisionsDebugMode", false),
    ])
    func linkOrPath(argument: String, isLink: Bool) {
        #expect(StoryArcLink.isLink(argument) == isLink)
    }

    @Test("A command line gives its paths and its links apart, and skips flags with their values")
    func commandLine() {
        let arguments = [
            "/Applications/StoryArc.app/Contents/MacOS/StoryArc", "-AppleShowScrollBars", "WhenScrolling",
            "storyarc://publication/Strip", "Saga 1.cbz", "/comics/Strip.cbt", "-NSQuitAlwaysKeepsWindows", "-x",
        ]
        let split = MacCommandLine.split(arguments, directory: URL(filePath: "/comics", directoryHint: .isDirectory))
        #expect(split.files.map { $0.path(percentEncoded: false) } == ["/comics/Saga 1.cbz", "/comics/Strip.cbt"])
        #expect(split.links.map(\.absoluteString) == ["storyarc://publication/Strip"])
        #expect(MacCommandLine.split(["StoryArc"], directory: URL(filePath: "/")).files.isEmpty)
    }

    @Test("The app registers the scheme the parser reads")
    func registersScheme() throws {
        let types = try #require(Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == [StoryArcLink.scheme])
    }
}
