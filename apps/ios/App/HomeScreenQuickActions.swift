import UIKit

import StoryArcCore

/// The menu the system shows when the app icon is held down.
///
/// `native-experience` names quick actions among the system affordances the app must use
/// rather than invent. Which entries the menu holds is decided by ``QuickActions`` in the
/// core, mirrored by Android; this file is only the platform's vocabulary for it.
///
/// The entries survive the app being killed because the system, not the app, stores them:
/// `UIApplication.shortcutItems` is written into the app's own state and read by
/// SpringBoard whether or not a process exists. That is also why the publication travels
/// as an identifier in `userInfo` rather than as a path — a menu can be older than the
/// scan that last placed the file.
@MainActor
enum HomeScreenActions {

    /// Where the continue entry keeps the publication it names.
    static let publicationKey = "publication"

    /// Replaces the menu with the entries the core says belong in it.
    ///
    /// A whole replacement rather than an edit: the list is short, it is derived from
    /// state the app already holds, and a menu assembled by mutation is a menu that can
    /// hold two continue entries for two different books.
    static func publish(_ actions: [QuickAction]) {
        UIApplication.shared.shortcutItems = actions.map(item(for:))
    }

    private static func item(for action: QuickAction) -> UIApplicationShortcutItem {
        switch action {
        case let .continueReading(id, title):
            // The act on the title line and the book on the subtitle, because the home
            // screen shows both. Android has one label at two lengths and puts them
            // together instead — the same two facts, laid out the way each platform lays
            // a menu row out.
            UIApplicationShortcutItem(
                type: action.id,
                localizedTitle: String(localized: "shortcut.continue", bundle: .main, locale: .storyArc),
                localizedSubtitle: title,
                icon: UIApplicationShortcutIcon(systemImageName: "book.pages"),
                userInfo: [publicationKey: id as NSString]
            )
        case .library:
            UIApplicationShortcutItem(
                type: action.id,
                localizedTitle: String(localized: "shortcut.library", bundle: .main, locale: .storyArc),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "books.vertical"),
                userInfo: nil
            )
        case .downloads:
            UIApplicationShortcutItem(
                type: action.id,
                localizedTitle: String(localized: "shortcut.downloads", bundle: .main, locale: .storyArc),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "arrow.down.circle"),
                userInfo: nil
            )
        }
    }

    /// What the reader chose, read back out of the entry the system handed over.
    static func request(from item: UIApplicationShortcutItem) -> QuickActionRequest? {
        QuickActionRequest(
            id: item.type,
            publicationID: item.userInfo?[publicationKey] as? String
        )
    }
}

/// The one thing a quick action has asked for, waiting for the interface to pick it up.
///
/// A shared inbox rather than a value passed down, because the two moments a quick action
/// arrives are on opposite sides of the app: a cold launch reaches the scene delegate
/// before SwiftUI has built anything, and a tap on a running app reaches it long after.
/// Both have to end up in the same place.
@MainActor
@Observable
final class QuickActionInbox {
    static let shared = QuickActionInbox()

    private(set) var pending: QuickActionRequest?

    private init() {}

    /// Files a request, and says whether it was one this app understands.
    ///
    /// The answer is what `windowScene(_:performActionFor:completionHandler:)` reports to
    /// the system, which is why an unrecognised entry returns `false` rather than being
    /// quietly dropped: an old menu on a home screen should look ignored, not broken.
    @discardableResult
    func receive(_ item: UIApplicationShortcutItem) -> Bool {
        guard let request = HomeScreenActions.request(from: item) else { return false }
        pending = request
        return true
    }

    /// Marks the request handled, so a redraw does not act on it twice.
    func clear() {
        pending = nil
    }
}

/// The scene's own delegate, for the one callback SwiftUI does not surface.
///
/// A quick action arrives at the *scene*, twice over: in the connection options on a cold
/// launch, and through `performActionFor` when the app is already running. SwiftUI's `App`
/// exposes neither, so this class is installed by ``OrientationDelegate`` through
/// `configurationForConnecting` and does nothing else — SwiftUI keeps the rest of the
/// scene's life.
@MainActor
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let item = connectionOptions.shortcutItem else { return }
        QuickActionInbox.shared.receive(item)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActionInbox.shared.receive(shortcutItem))
    }
}
