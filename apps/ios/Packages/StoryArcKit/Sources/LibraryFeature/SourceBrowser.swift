public import SwiftUI

internal import Catalogue
public import Persistence
public import StoryArcCore

/// The way in to one catalogue, server or share.
///
/// Extracted from `LibraryView` because a wide window reaches it through a sidebar
/// selection and a narrow one through a pushed destination, and two copies of a
/// four-way branch is how one of them ends up showing the wrong browser.
///
/// Three kinds of server, three browsers, one door out: whatever is opened goes to the
/// same reader a local publication does.
struct SourceBrowser: View {
    let source: Source
    let pins: CertificatePins
    let credentials: CredentialStore
    let kavitaProgress: KavitaProgressStore
    let lists: [ServerShelf]
    let onOpen: (Publication, URL) -> Void

    var body: some View {
        if let page = CataloguePage(source: source, credentials: credentials) {
            CatalogueBrowserView(
                title: page.title,
                url: page.url,
                credential: page.credential,
                pins: pins,
                onOpen: onOpen
            )
        } else if let page = SmbPage(source: source, credentials: credentials) {
            SmbBrowserView(
                title: page.title,
                address: page.address,
                path: page.address.path,
                onOpen: onOpen
            )
        } else if let page = KavitaPage(source: source, credentials: credentials) {
            KavitaBrowserView(
                title: page.title,
                address: page.address,
                sourceId: page.id,
                store: kavitaProgress,
                lists: lists,
                onOpen: onOpen
            )
        } else {
            // No page could be built, which means the secret this source needs is not in
            // the keychain any more. Saying so beats the blank screen this used to push —
            // a screen with nothing on it and no way to tell whether the server was slow
            // or the app was broken.
            UnreachableSource(name: source.displayName)
        }
    }
}
