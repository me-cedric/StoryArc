import SwiftUI

internal import DesignSystem
internal import Formats
import Kavita
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
    let onOpen: (Publication, URL) -> Void

    @State private var volumes: [KavitaVolume] = []
    @State private var metadata: KavitaMetadata?
    @State private var resume: KavitaChapter?
    @State private var fetching: Int?

    var body: some View {
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
                            ? String(localized: "kavita.looseChapters", bundle: .module)
                            : (volume.name ?? "\(volume.number)")
                    )
                }
            }
        }
        .navigationTitle(series.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard volumes.isEmpty else { return }
            volumes = (try? await client.volumes(ofSeries: series.id)) ?? []
            // Each on its own, because a server that cannot answer one of the three should
            // still show the other two rather than an empty screen.
            metadata = try? await client.metadata(ofSeries: series.id)
            resume = try? await client.continuePoint(ofSeries: series.id)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(chapter))
    }

    /// What a screen reader hears. The tick and the spinner carry no text of their own.
    private func spoken(_ chapter: KavitaChapter) -> String {
        if fetching == chapter.id {
            return "\(chapter.displayName), " +
                String(localized: "kavita.fetching", bundle: .module)
        }
        if chapter.isFinished {
            return "\(chapter.displayName), " +
                String(localized: "library.readState.finished", bundle: .module)
        }
        return chapter.displayName
    }

    /// Fetches a chapter and hands it to the reader.
    ///
    /// Into the caches directory, not the download store: `kavita-server` and
    /// `offline-downloads` are different promises, and a chapter opened once is not a
    /// download the reader asked to keep.
    private func open(_ chapter: KavitaChapter) async {
        fetching = chapter.id
        defer { fetching = nil }

        guard let data = try? await client.chapter(chapter.id) else { return }
        let directory = URL.cachesDirectory.appending(path: "Kavita", directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil else { return }

        let file = directory.appending(path: "chapter-\(chapter.id).cbz")
        guard (try? data.write(to: file, options: .atomic)) != nil,
              let publication = try? await PublicationIndexer.index(
                  fileAt: file,
                  seriesHint: series.name
              )
        else { return }
        onOpen(publication, file)
    }
}
