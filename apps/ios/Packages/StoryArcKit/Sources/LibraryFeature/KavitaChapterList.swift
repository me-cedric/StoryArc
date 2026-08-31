import SwiftUI

internal import DesignSystem
internal import Formats
import Kavita
import Persistence
import StoryArcCore

/// One series: what the server says about it, where to resume, and every chapter.
///
/// `kavita-server` asks for three things here -- the server's own metadata preferred over the
/// file's, volumes and loose chapters distinguished, and a "Continue" primary action pointing
/// at the chapter Kavita reports as next.
struct KavitaChapterList: View {
    @Environment(\.theme) private var theme

    let client: KavitaClient
    let series: KavitaSeries
    let sourceId: String
    let store: KavitaProgressStore
    /// The server's one search, carried down from the browser above. See ``KavitaFinder``.
    ///
    /// Nil for a chapter list reached *from* a search result, which is already inside one:
    /// that screen gets a finder of its own so a second search does not rewrite the first.
    var finder: KavitaFinder?
    /// Where a pulled position is written. Nil in a preview, which has no store to merge into.
    var progress: ProgressStore?
    /// This server's own reading lists, which its chapters may be added to.
    var lists: [ServerShelf] = []
    let onOpen: (Publication, URL) -> Void

    @State private var volumes: [KavitaVolume] = []
    @State private var metadata: KavitaMetadata?
    @State private var conflicts: [ProgressPull.Conflict] = []
    @State private var resume: KavitaChapter?
    @State private var fetching: Int?

    /// Which chapters this device already has a download of.
    ///
    /// Seeded from the cards rather than from the download library: a card names the chapter
    /// a download came from, and the download record is keyed on a publication identity that
    /// only exists once the file has been indexed.
    @State private var kept: Set<Int> = []

    /// The finder this screen uses when it was not handed one.
    @State private var ownFinder = KavitaFinder()

    private var search: KavitaFinder { finder ?? ownFinder }

    var body: some View {
        Group {
            if search.isShowing {
                KavitaHits(
                    finder: search,
                    client: client,
                    sourceId: sourceId,
                    store: store,
                    progress: progress,
                    lists: lists,
                    onOpen: onOpen
                )
            } else {
                chapters
            }
        }
        .navigationTitle(series.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .kavitaSearchable(search) { await search.run(client, sourceId: sourceId) }
        // `reading-progress`: a genuine conflict is one the reader "is told once — naming
        // both — with the option to take the other". Once, not per chapter: a server that
        // has moved on in six places is one thing that happened, and six alerts about it
        // would be the app making a reader dismiss its own synchronisation.
        .alert(
            Text("sync.conflict.title", bundle: .module),
            isPresented: Binding(
                get: { !conflicts.isEmpty },
                set: { if !$0 { conflicts = [] } }
            )
        ) {
            Button(role: .cancel) { conflicts = [] } label: {
                Text("sync.conflict.keep", bundle: .module)
            }
            Button {
                // Taking the other means writing back what was set aside — the reader
                // saying the further position was not theirs.
                let discarded = conflicts
                conflicts = []
                Task {
                    for conflict in discarded {
                        var restored = conflict.resolved
                        restored.position = conflict.discarded
                        try? await progress?.save(restored)
                    }
                }
            } label: {
                Text("sync.conflict.take", bundle: .module)
            }
        } message: {
            Text("sync.conflict.body \(conflicts.count)", bundle: .module)
        }
        .task {
            guard volumes.isEmpty else { return }
            kept = Set(KavitaCardStore().all(from: sourceId).map(\.chapterId))
            volumes = (try? await client.volumes(ofSeries: series.id)) ?? []
            // Each on its own, because a server that cannot answer one of the three should
            // still show the other two rather than an empty screen.
            metadata = try? await client.metadata(ofSeries: series.id)
            resume = try? await client.continuePoint(ofSeries: series.id)
            // `reading-progress`: "when a synchronising source refreshes, progress recorded
            // on other devices is merged into the local store". This is that refresh — the
            // chapters have just arrived carrying what the server thinks has been read.
            if let progress {
                conflicts = await KavitaSync.pull(
                    volumes.flatMap(\.chapters),
                    in: store,
                    into: progress,
                    of: sourceId,
                    to: client.address
                )
            }
        }
    }

    /// The series' own screen: where to resume, what the server says, and every chapter.
    private var chapters: some View {
        List {
            if let resume {
                Button {
                    Task { await open(resume) }
                } label: {
                    Text("kavita.continue \(resume.displayName)", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(fetching != nil)
                .listRowSeparator(.hidden)
            }

            if let metadata {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    if let summary = metadata.summary, !summary.isEmpty {
                        Text(summary)
                            .textRole(.body)
                            .foregroundStyle(theme.palette.textPrimary)
                    }
                    if !metadata.facts.isEmpty {
                        Text(metadata.facts.joined(separator: " · "))
                            .textRole(.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }

            ForEach(volumes) { volume in
                Section {
                    ForEach(volume.chapters) { chapter in
                        row(chapter)
                    }
                } header: {
                    // Loose chapters are not a volume, and labelling them as one would
                    // invent a "Volume 0" the server never had.
                    Text(
                        volume.isLooseChapters
                            ? String(localized: "kavita.looseChapters", bundle: .module, locale: .storyArc)
                            : (volume.name ?? "\(volume.number)")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ chapter: KavitaChapter) -> some View {
        Button {
            Task { await open(chapter) }
        } label: {
            HStack(spacing: StoryArcSpace.sm) {
                Text(chapter.displayName)
                    .foregroundStyle(theme.palette.textPrimary)

                Spacer(minLength: 0)

                if fetching == chapter.id {
                    ProgressView()
                } else if chapter.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(StoryArcColor.Status.success)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(fetching != nil)
        .contextMenu { actions(for: chapter) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(chapter))
    }

    /// What else can be done with one chapter.
    ///
    /// `kavita-server`: marking read must reach the server so its own UI agrees, and a
    /// context menu is where iOS puts the rest. Its own builder rather than inline, because
    /// the row it hangs off is already at the length the linter allows.
    @ViewBuilder
    private func actions(for chapter: KavitaChapter) -> some View {
        // `kavita-server` has a scenario about opening "a downloaded Kavita publication"
        // offline, and until this there was no way to have one: the browser wrote every
        // chapter to the caches directory. This is the asking.
        Button {
            Task { await keep(chapter) }
        } label: {
            Label(
                String(localized: "kavita.keep", bundle: .module, locale: .storyArc),
                systemImage: "arrow.down.circle"
            )
        }
        .disabled(kept.contains(chapter.id))

        Button {
            Task { await mark(chapter, read: !chapter.isFinished) }
        } label: {
            Label(
                chapter.isFinished
                    ? String(localized: "library.mark.unread", bundle: .module, locale: .storyArc)
                    : String(localized: "library.mark.read", bundle: .module, locale: .storyArc),
                systemImage: chapter.isFinished ? "circle" : "checkmark.circle"
            )
        }

        // Only this server's own lists: a Kavita list can hold nothing else, and offering
        // another server's would be offering a refusal.
        ForEach(lists.filter { $0.server.id == sourceId }) { list in
            Button {
                Task { await add(chapter, to: list) }
            } label: {
                Label(
                    String(
                        format: String(localized: "kavita.addToList %@", bundle: .module, locale: .storyArc),
                        list.title
                    ),
                    systemImage: "text.append"
                )
            }
        }
    }

    /// What a screen reader hears. The tick and the spinner carry no text of their own.
    private func spoken(_ chapter: KavitaChapter) -> String {
        if fetching == chapter.id {
            return "\(chapter.displayName), " +
                String(localized: "kavita.fetching", bundle: .module, locale: .storyArc)
        }
        if chapter.isFinished {
            return "\(chapter.displayName), " +
                String(localized: "library.readState.finished", bundle: .module, locale: .storyArc)
        }
        return chapter.displayName
    }

    /// Fetches a chapter and hands it to the reader.
    ///
    /// Into the caches directory, not the download store: `kavita-server` and
    /// `offline-downloads` are different promises, and a chapter opened once is not a
    /// download the reader asked to keep.
    /// Keeps a chapter on the device, with what the server says about it.
    ///
    /// The record and the card, not just the bytes: see ``KavitaKeep``. The chapter is not
    /// opened afterwards — the reader asked to keep it, which is a different act from asking
    /// to read it, and jumping into the reader would answer a question nobody put.
    private func keep(_ chapter: KavitaChapter) async {
        fetching = chapter.id
        defer { fetching = nil }
        let done = await KavitaKeep.keep(
            KavitaKeep.Subject(
                chapter: chapter,
                series: series,
                metadata: metadata,
                origin: origin(of: chapter),
                sourceID: UUID(uuidString: sourceId)
            ),
            client: client,
            progress: store
        )
        if done != nil { kept.insert(chapter.id) }
    }

    /// Tells the server the reader has, or has not, read this chapter.
    private func mark(_ chapter: KavitaChapter, read isRead: Bool) async {
        await KavitaSync.mark(
            isRead,
            for: origin(of: chapter),
            to: client.address,
            in: store
        )
        volumes = (try? await client.volumes(ofSeries: series.id)) ?? volumes
    }

    /// Puts a chapter in one of this server's reading lists.
    private func add(_ chapter: KavitaChapter, to list: ServerShelf) async {
        await KavitaSync.append(list.id, for: origin(of: chapter), to: client.address, in: store)
    }

    /// Where a chapter sits on the server, which every write needs to name.
    private func origin(of chapter: KavitaChapter) -> KavitaOrigin {
        KavitaOrigin(
            sourceId: sourceId,
            libraryId: series.libraryId,
            seriesId: series.id,
            volumeId: volumes.first { $0.chapters.contains(chapter) }?.id ?? 0,
            chapterId: chapter.id
        )
    }

    private func open(_ chapter: KavitaChapter) async {
        fetching = chapter.id
        defer { fetching = nil }

        guard let fetched = try? await client.chapter(chapter.id),
              let file = kavitaCacheFile(
                  chapterId: chapter.id,
                  mediaType: fetched.mediaType,
                  // The series, so the indexer reads it back out. Kavita's own chapter
                  // number after it, which is what tells one cached file from the next.
                  named: "\(series.name) \(chapter.number)"
              )
        else { return }
        guard (try? fetched.bytes.write(to: file, options: .atomic)) != nil,
              let publication = try? await PublicationIndexer.index(
                  fileAt: file,
                  catalogueSeries: series.name
              )
        else { return }

        // The note the reader cannot leave for itself: it opens a file and knows nothing
        // about servers, so this is what lets the position get home.
        store.remember(origin(of: chapter), for: publication.id)
        onOpen(publication, file)
    }
}

/// Where a fetched chapter is written, named for what it actually is.
///
/// `kavita-server` serves comics and books from the same endpoint, and the reader the app
/// opens is chosen by the file's format. Writing every chapter as `.cbz` sent an EPUB to the
/// comic reader, which spun for ever on a file it could not page.
/// Where a chapter fetched from a server is kept while it is read.
///
/// The chapter's id is the *directory* and the name is the publication's own. It used to be
/// the other way round, and `chapter-5.cbz` was then the only name anything downstream had:
/// the indexer reads a series out of a filename, so every chapter of one series landed on a
/// shelf of its own, and `comic-reader`'s "applies to the series" applied to one chapter.
/// The id still makes the path unique; it no longer has to be the name as well.
func kavitaCacheFile(chapterId: Int, mediaType: String?, named: String? = nil) -> URL? {
    let directory = URL.cachesDirectory
        .appending(path: "Kavita", directoryHint: .isDirectory)
        .appending(path: String(chapterId), directoryHint: .isDirectory)
    guard (try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )) != nil else { return nil }

    let format = mediaType.flatMap(PublicationFormat.init(mediaType:))
    let ext = format.map { String(describing: $0).lowercased() } ?? "cbz"
    // A path separator in a server's title would make a directory rather than a name.
    let stem = (named?.replacingOccurrences(of: "/", with: "-")).flatMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    } ?? "chapter-\(chapterId)"
    return directory.appending(path: "\(stem).\(ext)")
}
