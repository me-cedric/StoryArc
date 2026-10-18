import Foundation
import StoryArcCore

/// The app's own address scheme, `storyarc://`.
///
/// `desktop-experience`, *Opening a link or a command*. Two forms open something:
/// `storyarc://publication/<title or id>` and `storyarc://source/<name or id>`, the name
/// percent-encoded. Anything else, an unknown kind, a path of several parts, no name, is refused
/// whole. A query or a fragment after a name is ignored: a link is a name to open and never a
/// command, so nothing here reads a setting, runs a program or writes data. The Mac twin of the
/// Windows `StoryArcLink` (task 5.8), and as pure: the caller passes what the library holds.
enum StoryArcLink {
    static let scheme = "storyarc"

    enum Action: Equatable {
        /// A publication the library holds: it opens in a reader window.
        case open(Publication)
        /// A source the app holds: Preferences opens on the Sources tab.
        case showSource(Source)
        /// A publication or a source the app does not hold: named in grey, nothing changes.
        case notFound(String)
        /// Nothing to open, or something other than a name: nothing runs and nothing changes.
        case refused
    }

    /// Whether a URL or a command-line argument is a link rather than a file.
    static func isLink(_ argument: String) -> Bool {
        argument.lowercased().hasPrefix(scheme + ":")
    }

    static func resolve(_ link: URL, publications: [Publication], sources: [Source]) -> Action {
        guard link.scheme?.lowercased() == scheme, let kind = link.host(percentEncoded: false) else { return .refused }
        // Split before decoding: an id may hold an encoded `/`, and it is still one name.
        let parts = link.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 1, let decoded = parts[0].removingPercentEncoding else { return .refused }
        let name = decoded.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .refused }
        switch kind.lowercased() {
        case "publication":
            let found = publications.first { matches(name, $0.id, $0.displayTitle) }
            return found.map(Action.open) ?? .notFound(name)
        case "source":
            let found = sources.first { matches(name, $0.id.uuidString, $0.displayName) }
            return found.map(Action.showSource) ?? .notFound(name)
        default:
            return .refused
        }
    }

    private static func matches(_ wanted: String, _ id: String, _ title: String) -> Bool {
        wanted.caseInsensitiveCompare(id) == .orderedSame || wanted.caseInsensitiveCompare(title) == .orderedSame
    }
}

/// The files and links of a command line, `StoryArc.app/Contents/MacOS/StoryArc <path> …`.
///
/// `desktop-experience`, *The command line*. The first argument is the program. An argument that
/// starts with `-` is a flag, and the value after it is the flag's (`-AppleShowScrollBars
/// WhenScrolling`, as the test scheme passes), so neither is a file. A link is a link and never a
/// path; every other argument is a path, relative to the working directory.
enum MacCommandLine {
    static func split(_ arguments: [String], directory: URL) -> (files: [URL], links: [URL]) {
        var files: [URL] = []
        var links: [URL] = []
        var rest = arguments.dropFirst()[...]
        while let argument = rest.popFirst() {
            if argument.hasPrefix("-") {
                if let value = rest.first, !value.hasPrefix("-"), !StoryArcLink.isLink(value) { rest.removeFirst() }
            } else if StoryArcLink.isLink(argument) {
                if let link = URL(string: argument) { links.append(link) }
            } else {
                files.append(URL(filePath: argument, relativeTo: directory).standardizedFileURL)
            }
        }
        return (files, links)
    }
}
