import Foundation
import StoryArcCore

/// What one reader window reads: one publication, at one file.
///
/// `desktop-experience`, *The window model*: one window per publication, and a second open
/// of the same publication focuses the first. SwiftUI's `openWindow(value:)` fronts the
/// window whose value is *equal* to the one asked for, so equality here is the publication
/// and nothing else — the path is carried for restoration and plays no part in identity.
/// Task 2.9 of `desktop-clients`.
struct ReaderTarget: Codable, Hashable, Sendable {
    let publicationID: String
    /// Where the file was when the window opened. Restoration re-checks it.
    let path: String
    let title: String

    init(publicationID: String, path: String, title: String) {
        self.publicationID = publicationID
        self.path = path
        self.title = title
    }

    init(publication: Publication, url: URL) {
        self.init(
            publicationID: publication.id,
            path: url.standardizedFileURL.path(percentEncoded: false),
            title: publication.displayTitle
        )
    }

    var url: URL { URL(filePath: path) }

    static func == (lhs: ReaderTarget, rhs: ReaderTarget) -> Bool {
        lhs.publicationID == rhs.publicationID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(publicationID)
    }
}

/// A reader window's saved state: what it reads and where it sat.
struct ReaderSession: Codable, Equatable, Sendable {
    let target: ReaderTarget
    /// The window's frame in screen coordinates, or `nil` before it was ever placed.
    var frame: CGRect?
}

/// What a request to open a publication does, given the windows already open.
enum OpenDecision: Equatable, Sendable {
    /// A window already reads it: bring that one to the front.
    case focus(ReaderTarget)
    /// Nothing reads it yet: open a window.
    case open(ReaderTarget)
}

/// The reader windows that are open, and the record a relaunch restores them from.
///
/// SwiftUI's own window restoration is turned off on the reader group
/// (`.restorationBehavior(.disabled)`) because it would reopen a window whose publication
/// is gone; `RestorationPlan` decides instead, and the library names the ones that could
/// not come back, as the spec's *A publication that cannot be reopened* scenario asks.
@MainActor
@Observable
final class ReaderWindows {
    static let shared = ReaderWindows()
    static let defaultsKey = "app.storyarc.mac.readerSessions"

    private(set) var sessions: [ReaderSession] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var open: [ReaderTarget] { sessions.map(\.target) }

    func decide(_ target: ReaderTarget) -> OpenDecision {
        if let existing = sessions.first(where: { $0.target == target }) {
            return .focus(existing.target)
        }
        return .open(target)
    }

    func didOpen(_ target: ReaderTarget) {
        guard !sessions.contains(where: { $0.target == target }) else { return }
        sessions.append(ReaderSession(target: target))
        persist()
    }

    func didClose(_ target: ReaderTarget) {
        sessions.removeAll { $0.target == target }
        persist()
    }

    func didPlace(_ target: ReaderTarget, at frame: CGRect) {
        guard let index = sessions.firstIndex(where: { $0.target == target }) else { return }
        guard sessions[index].frame != frame else { return }
        sessions[index].frame = frame
        persist()
    }

    func frame(of target: ReaderTarget) -> CGRect? {
        sessions.first { $0.target == target }?.frame
    }

    /// What the last run left open, read once at launch before anything is opened.
    func savedSessions() -> [ReaderSession] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([ReaderSession].self, from: data)
        else { return [] }
        return saved
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Which saved reader windows a launch reopens, and which it names instead.
enum RestorationPlan {
    struct Outcome: Equatable, Sendable {
        let reopen: [ReaderSession]
        /// Named in the library in grey. Their page stays in the progress store untouched.
        let missing: [ReaderTarget]
    }

    static func plan(saved: [ReaderSession], isReachable: (ReaderTarget) -> Bool) -> Outcome {
        var reopen: [ReaderSession] = []
        var missing: [ReaderTarget] = []
        for session in saved where !reopen.contains(where: { $0.target == session.target }) {
            if isReachable(session.target) {
                reopen.append(session)
            } else {
                missing.append(session.target)
            }
        }
        return Outcome(reopen: reopen, missing: missing)
    }

    /// A saved frame, or `nil` when no connected display holds any of it.
    ///
    /// *A display that is gone*: the window then opens at the group's default, fully
    /// visible on a display that exists, rather than off every screen.
    static func visibleFrame(_ frame: CGRect?, screens: [CGRect]) -> CGRect? {
        guard let frame else { return nil }
        return screens.contains { $0.intersects(frame) } ? frame : nil
    }
}
