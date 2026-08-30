import CoreSpotlight
import SwiftUI

import LibraryFeature
import StoryArcCore

/// The publication being read, described to the system.
///
/// `native-experience` asks for Handoff, which on iOS is one type doing two jobs: an
/// `NSUserActivity` marked eligible for handoff is offered on the reader's other devices,
/// and the same activity marked eligible for search is what puts the book in Spotlight.
/// One activity rather than two because they describe the same fact — this person is
/// reading this book — and two would drift.
///
/// It carries an identifier, not a path. A path is true on one device and means nothing on
/// another, and ADR-0006 already has a key that is stable across sources. Nothing is sent
/// anywhere: the receiving device is told which publication, and looks in its own library.
/// There is no backend and this does not invent one — a book the other device does not
/// have is a book it cannot open, and it says so by doing nothing.
enum ReadingActivity {
    static let type = "app.storyarc.reading"
    private static let publicationKey = "publication"

    /// Fills in what the system will show and hand on.
    static func describe(_ publication: Publication, in activity: NSUserActivity) {
        activity.title = publication.displayTitle
        activity.userInfo = [publicationKey: publication.id]
        activity.requiredUserInfoKeys = [publicationKey]
        // Deduplicates the Spotlight entry across launches, and is the handle a later
        // deletion would use. Without it every launch indexes the same book again.
        activity.persistentIdentifier = publication.id
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        // The system may offer it on the lock screen and in Shortcuts. It is a reading
        // position, not a behaviour profile — nothing about it leaves the device.
        activity.isEligibleForPrediction = true
        activity.keywords = Set([publication.displayTitle, publication.series].compactMap { $0 })

        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = publication.displayTitle
        attributes.contentDescription = [publication.series, publication.authors.first]
            .compactMap { $0 }
            .joined(separator: " — ")
        activity.contentAttributeSet = attributes
    }

    /// Which publication an activity was about, when it was one of ours.
    static func publicationID(in activity: NSUserActivity) -> String? {
        activity.userInfo?[publicationKey] as? String
    }
}

/// Everything that gets a reader back to their book from outside the app.
///
/// Two doors, one hallway: the home-screen menu and Handoff both end up naming a
/// publication by identifier, and both then have to wait for the library to be able to
/// place it. Written as one modifier so that waiting exists once.
///
/// Kept out of `StoryArcApp` because the app file is already at the length the linter
/// allows, and because none of this is wiring between screens — it is the app's
/// conversation with the system.
struct ReadingContinuity: ViewModifier {
    /// What the reader has open, so the activity describes the right book.
    let reading: ReadingSelection?
    /// The library, which is what can turn an identifier back into a publication.
    let library: LibraryModel
    /// Whether the downloads entry has anywhere to go.
    let hasDownloads: Bool

    let onOpen: (Publication) -> Void
    /// Where to land when the action named a place rather than a book. Never called with
    /// ``QuickActionRequest/continueReading(id:)`` — that one is waited for here.
    let onShow: (QuickActionRequest) -> Void

    /// A publication asked for by identifier, still waiting to be found.
    @State private var wanted: String?

    /// How long to keep looking for a publication the library has not listed yet.
    ///
    /// `sources` restores the cached catalogue before it walks anything, so the usual
    /// answer arrives in a frame or two. The cap is what stops a cold start with a slow
    /// share from yanking the reader into a book five minutes after they asked, by which
    /// time they are somewhere else.
    private static let attempts = 20
    private static let betweenAttempts = Duration.milliseconds(250)

    private var offered: [QuickAction] {
        QuickActions.offered(continuing: library.continueReading.first, hasDownloads: hasDownloads)
    }

    /// The menu, and the language it will be written in.
    ///
    /// The language is part of the key because a menu already on the home screen keeps the
    /// words it was published with: `localization` lets a reader switch language without a
    /// restart, and without this the entries would still be in the old one. Android
    /// republishes for the same reason, by rebuilding the activity.
    private struct Menu: Equatable {
        let actions: [QuickAction]
        let language: String?
    }

    private var menu: Menu { Menu(actions: offered, language: InterfaceLanguage.tag) }

    func body(content: Content) -> some View {
        content
            // Republished whenever the list itself changes, which is the reading position
            // changing, a download arriving, or a publication being finished. The reader
            // closing a book is what refreshes progress, so the menu is right by the time
            // they are back on the home screen.
            .task(id: menu) { HomeScreenActions.publish(menu.actions) }
            .task(id: QuickActionInbox.shared.pending) { take(QuickActionInbox.shared.pending) }
            .userActivity(ReadingActivity.type, isActive: reading != nil) { activity in
                guard let publication = reading?.publication else { return }
                ReadingActivity.describe(publication, in: activity)
            }
            // Handoff from another device, and a tap on the Spotlight result, arrive here
            // as the same thing: a publication named by identifier.
            .onContinueUserActivity(ReadingActivity.type) { activity in
                wanted = ReadingActivity.publicationID(in: activity)
            }
            .task(id: wanted) { await settle() }
    }

    /// Acts on a quick action, or waits for the library if it named a book.
    private func take(_ request: QuickActionRequest?) {
        guard let request else { return }
        QuickActionInbox.shared.clear()
        switch request {
        case let .continueReading(id): wanted = id
        case .library, .downloads: onShow(request)
        }
    }

    /// Waits for the library to be able to place the publication that was asked for.
    ///
    /// A wait rather than a lookup, because a quick action or a Handoff can land on a cold
    /// launch: the app is being built at the moment the request arrives and the shelf is
    /// still empty. Giving up is part of the behaviour, not a failure of it — the reader
    /// lands on the library, which is where they would have landed anyway.
    private func settle() async {
        guard let id = wanted else { return }
        for _ in 0 ..< Self.attempts {
            if let publication = library.publications.first(where: { $0.id == id }) {
                wanted = nil
                onOpen(publication)
                return
            }
            do {
                try await Task.sleep(for: Self.betweenAttempts)
            } catch {
                return
            }
        }
        wanted = nil
    }
}

extension View {
    /// See ``ReadingContinuity``.
    func continuing(
        reading: ReadingSelection?,
        library: LibraryModel,
        hasDownloads: Bool,
        onOpen: @escaping (Publication) -> Void,
        onShow: @escaping (QuickActionRequest) -> Void
    ) -> some View {
        modifier(
            ReadingContinuity(
                reading: reading,
                library: library,
                hasDownloads: hasDownloads,
                onOpen: onOpen,
                onShow: onShow
            )
        )
    }
}
