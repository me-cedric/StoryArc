import Foundation
import StoryArcCore

/// What a publication's page says, decided before it is drawn.
///
/// `publication-detail` on a desktop, task 2.23d: one primary action, a line that names
/// where the file lives, and the honest absences — no cover, an offline source, nothing
/// read yet.
struct DetailPresentation: Equatable, Sendable {
    enum PrimaryAction: Equatable, Sendable {
        case read
        case `continue`(page: Int, of: Int)
        case readAgain
        /// The file is not reachable: the button is absent and the line says why in grey.
        case unavailable
    }

    let primary: PrimaryAction
    /// The folder the file sits in, or the reason it cannot be reached.
    let whereItLives: String
    let hasCover: Bool
    let isGrey: Bool

    static func make(
        publication: Publication,
        location: URL?,
        isReachable: Bool,
        progress: ReadingProgress?,
        hasCover: Bool,
        home: URL = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    ) -> DetailPresentation {
        let primary: PrimaryAction
        if location == nil || !isReachable {
            primary = .unavailable
        } else if let progress, progress.isFinished {
            primary = .readAgain
        } else if let progress, case let .page(index, total) = progress.position, index > 0 {
            primary = .continue(page: index + 1, of: total)
        } else {
            primary = .read
        }
        let place: String
        if let location {
            place = isReachable ? Self.folderName(of: location, home: home) : Self.unavailableName(of: location)
        } else {
            place = ""
        }
        return DetailPresentation(
            primary: primary, whereItLives: place, hasCover: hasCover, isGrey: primary == .unavailable
        )
    }

    /// The containing folder, with the home directory shortened to `~`.
    static func folderName(of url: URL, home: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        let homeParts = home.standardizedFileURL.pathComponents
        if folder.starts(with: homeParts) {
            let rest = folder.dropFirst(homeParts.count)
            return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
        }
        return "/" + folder.dropFirst().joined(separator: "/")
    }

    /// Where it was, when it is not there now: the volume for a path under /Volumes.
    static func unavailableName(of url: URL) -> String {
        let parts = url.standardizedFileURL.pathComponents
        if parts.count > 2, parts[1] == "Volumes" { return parts[2] }
        return url.deletingLastPathComponent().lastPathComponent
    }
}
