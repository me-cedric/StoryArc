import DesignSystem
import Formats
import Playback
import StoryArcCore
import SwiftUI

/// An audiobook's chapters on its publication page (`audio-playback`, *The chapter list on the publication's
/// page*, *Starting from a chapter*, *An audiobook with one part*): each chapter's name and length, whether it
/// is heard, in progress with what is left, or ahead, the phones' `ChapterProgress` rule; a chapter starts the
/// book there. A one-part book draws no list and states its length instead.
struct DetailAudioChapters: View {
    @Environment(\.theme) private var theme
    let publication: Publication
    let url: URL
    let record: ReadingProgress?
    let onStart: (Int) -> Void
    @State private var parts: [AudiobookPart] = []

    var body: some View {
        Group {
            if parts.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("desktop.detail.chapters").scaledFont(.headline)
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        Button { onStart(index) } label: { row(index, part) }
                            .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
            } else if let duration = parts.first?.duration {
                Text("desktop.detail.length \(SleepMenu.clock(duration))")
                    .scaledFont(.callout)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .task(id: url) { parts = await Self.parts(of: url) }
    }

    private func row(_ index: Int, _ part: AudiobookPart) -> some View {
        let reached = Self.reached(record)
        let mark = ChapterProgress.mark(of: index, reached: reached?.part, isFinished: record?.isFinished ?? false)
        let left = ChapterProgress.remainder(ofChapterLasting: part.duration, mark: mark, at: reached?.offset ?? 0)
        return HStack(spacing: 10) {
            Image(systemName: mark.glyph).foregroundStyle(mark == .unplayed ? theme.palette.textTertiary : theme.accent)
            Text(part.title ?? PlayerWindow.partName(index)).scaledFont(.body)
            Spacer()
            if let left {
                Text("desktop.player.chapter.left \(SleepMenu.clock(left))").scaledFont(.callout)
            } else if let duration = part.duration {
                Text(SleepMenu.clock(duration)).scaledFont(.callout).monospacedDigit()
            }
        }
        .foregroundStyle(theme.palette.textPrimary)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The part and offset a listening record reached, or nil for a book never started.
    static func reached(_ record: ReadingProgress?) -> (part: Int, offset: TimeInterval)? {
        guard case let .listening(part, _, offset, _)? = record?.position else { return nil }
        return (part, offset)
    }

    /// What the primary action says for an audiobook (`audio-playback`, *The primary action says where it will
    /// resume*): listen, or resume the chapter it stopped in, by name.
    enum Primary: Equatable {
        case listen
        case continueListening
        case resume(String)

        var key: LocalizedStringKey {
            switch self {
            case .listen: "desktop.detail.listen"
            case .continueListening: "desktop.detail.continueListening"
            case let .resume(chapter): "desktop.detail.resumeChapter \(chapter)"
            }
        }
    }

    static func primary(_ record: ReadingProgress?, parts: [AudiobookPart]) -> Primary {
        guard let reached = reached(record), record?.isFinished != true else { return .listen }
        guard parts.count > 1, parts.indices.contains(reached.part) else { return .continueListening }
        return .resume(parts[reached.part].title ?? PlayerWindow.partName(reached.part))
    }

    static func parts(of url: URL) async -> [AudiobookPart] {
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder)
        if isFolder.boolValue { return await AudiobookReader.read(folderAt: url).parts }
        return await AudiobookReader.read(fileAt: url).parts
    }
}
