internal import SwiftUI

internal import Catalogue
internal import DesignSystem
internal import StoryArcCore

/// One named run of a catalogue, shown as the feed declared it.
///
/// `opds-catalog` browses what the server says, and an OPDS 2.0 server says "Recently
/// added" and "Staff picks" are two things. Poured into one grid they were neither: the
/// titles vanished and the reader got an undivided run of covers in whatever order the
/// groups happened to be serialised in.
///
/// A strip rather than a grid, because a group is a *sample* — the feed sends the first
/// handful and a link to the rest, and a full-width grid of six covers would claim the
/// group has six things in it.
struct CatalogueGroupSection: View {
    @Environment(\.theme) private var theme

    let group: OpdsGroup

    /// The page this group belongs to, for the credential and the pins a section of it
    /// inherits.
    let browser: CatalogueBrowser

    let queue: DownloadQueue
    let onDevice: Set<String>
    let onOpen: (Publication, URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            header

            // A group can hold sections as well as publications — the standard lets it hold
            // whatever a feed holds — so both are shown rather than only the ones a
            // catalogue happens to use most.
            ForEach(group.navigation) { section in
                CatalogueSectionLink(section: section, browser: browser, onOpen: onOpen)
            }

            if !group.publications.isEmpty {
                strip
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: StoryArcSpace.sm) {
            Text(group.title)
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)

            Spacer(minLength: 0)

            // Only where the group says where the rest of it is. A "see all" that led back
            // to the page it is already on is a control that does nothing.
            if let more = group.more {
                NavigationLink {
                    CatalogueBrowserView(
                        title: group.title,
                        url: more,
                        credential: browser.credential,
                        pins: browser.pins,
                        origin: browser.origin,
                        onOpen: onOpen
                    )
                } label: {
                    HStack(spacing: StoryArcSpace.hair) {
                        Text("catalogue.group.more", bundle: .module)
                        Image(systemName: "chevron.right")
                    }
                    .textRole(.subheadline)
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text("catalogue.group.more.hint \(group.title)", bundle: .module)
                )
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: StoryArcSpace.md) {
                ForEach(group.publications) { entry in
                    CatalogueEntryLink(
                        entry: entry,
                        browser: browser,
                        queue: queue,
                        isDownloaded: onDevice.contains(entry.id),
                        onOpen: onOpen
                    )
                    .frame(width: StoryArcSpace.huge * 2)
                }
            }
            // The cells are drawn edge to edge inside the page's own gutter, so the strip
            // reaches the screen edge and the covers do not sit in a second inset.
            .padding(.vertical, StoryArcSpace.hair)
        }
        .scrollIndicators(.hidden)
    }
}

/// A section of a catalogue as a way in: the row, and the page it opens.
///
/// One view rather than a `NavigationLink` written at both call sites, because the feed's
/// own navigation and a group's navigation open the same kind of page and drifting apart
/// would mean a section inside a group lost the reader's pinned certificate.
struct CatalogueSectionLink: View {
    let section: OpdsSection
    let browser: CatalogueBrowser
    let onOpen: (Publication, URL) -> Void

    var body: some View {
        NavigationLink {
            CatalogueBrowserView(
                title: section.title,
                url: section.href,
                credential: browser.credential,
                pins: browser.pins,
                origin: browser.origin,
                onOpen: onOpen
            )
        } label: {
            CatalogueSectionRow(section: section)
        }
        .buttonStyle(.plain)
    }
}

/// A section, with its count where the feed gave one.
struct CatalogueSectionRow: View {
    @Environment(\.theme) private var theme

    let section: OpdsSection

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(section.title)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)

                if let count = section.count {
                    Text("catalogue.section.count \(count)", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
        }
        .padding(StoryArcSpace.md)
        .frame(minHeight: StoryArcSpace.xxl + StoryArcSpace.md)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.lg))
    }
}

/// A publication in a catalogue, and the screen that describes it.
///
/// A tap opens the detail screen rather than starting a download. `opds-catalog` puts the
/// choice of format "on the publication detail screen", and a grid where the tap committed
/// to a format left the reader nowhere to make it — the choice lived in a long-press menu,
/// which is a place readers do not look.
struct CatalogueEntryLink: View {
    let entry: OpdsEntry
    let browser: CatalogueBrowser
    let queue: DownloadQueue
    let isDownloaded: Bool
    let onOpen: (Publication, URL) -> Void

    /// The download the reader is being asked to spend mobile data on, if one is.
    @State private var meteredAsk: MeteredAsk?

    var body: some View {
        NavigationLink {
            CatalogueDetailView(
                entry: entry,
                credential: browser.credential,
                client: browser.client,
                queue: queue,
                onOpen: onOpen
            )
        } label: {
            CatalogueEntryCell(
                entry: entry,
                credential: browser.credential,
                client: browser.client,
                isDownloaded: isDownloaded
            )
        }
        .buttonStyle(.plain)
        // Never disabled, even with nothing readable on offer. The detail screen is where
        // `opds-catalog` requires the app to name "the formats offered" and to state that an
        // acquisition type is unsupported, and a cell that refused to open was a refusal
        // with no explanation attached.
        // What the menu keeps is the shortcut, not the decision. `offline-downloads`: "the
        // app SHALL let a user download any publication from a remote source for offline
        // reading" — a reader packing for a flight wants the download without the reading,
        // and without a walk through the detail screen either.
        .contextMenu {
            if isDownloaded {
                Button(role: .destructive) {
                    queue.remove(entry.id)
                } label: {
                    Text("downloads.remove", bundle: .module)
                }
            } else if let best = CatalogueAcquisition.best(of: entry) {
                Button {
                    // `offline-downloads`' *Overriding once*: on a metered link the reader
                    // is asked, with the size, before a byte of their allowance is spent.
                    // Off it, the tap is the whole interaction it has always been.
                    if queue.needsMeteredConfirmation(entry) {
                        meteredAsk = MeteredAsk(
                            entry: entry,
                            acquisition: best,
                            bytes: queue.statedBytes(of: entry)
                        )
                    } else {
                        queue.enqueue(entry, using: best)
                    }
                } label: {
                    Text("catalogue.acquire.download", bundle: .module)
                }
            }
        }
        .meteredConfirmation($meteredAsk) { asked in
            // The grant is this publication's, not the queue's: everything else behind it
            // goes on waiting for Wi-Fi.
            queue.enqueue(
                asked.entry,
                using: asked.acquisition,
                overridingMeteredConnection: true
            )
        }
    }
}
