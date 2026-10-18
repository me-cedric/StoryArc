import DesignSystem
import Playback
import StoryArcCore
import SwiftUI

/// The session, at the foot of the library while it runs (`audio-playback`, *The compact bar*, *Both sources look
/// the same*): the title and the chapter, play and pause, and the way back, which is the player window for a
/// narrated book and the book itself for a voice reading one. The same bar for both sources, as on the phones.
struct CompactPlayerBar: View {
    @Environment(\.theme) private var theme
    let centre: PlayerCentre
    let openReader: (ReaderTarget) -> Void

    var body: some View {
        if let compact = centre.compact {
            HStack(spacing: 12) {
                Button { openReader(Self.target(of: compact.book)) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: compact.wayBack == .fullPlayer ? "headphones" : "text.book.closed")
                            .font(.system(size: 18))
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(compact.label.title).scaledFont(.callout, weight: .semibold).lineLimit(1)
                            if let detail = compact.label.detail {
                                Text(detail).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("desktop.player.compact.open \(compact.label.title)"))
                Button { centre.toggle() } label: {
                    Image(systemName: compact.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .hitTarget(HitTarget.icon)
                .accessibilityLabel(Text(compact.isPlaying ? "desktop.player.pause" : "desktop.player.play"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .storyArcGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("desktop.player.compact"))
        }
    }

    /// The window the bar goes back to: the player window for an audiobook, the reader for a book read aloud.
    static func target(of book: SpokenBook) -> ReaderTarget {
        ReaderTarget(
            publicationID: book.publication.id, path: book.url.path(percentEncoded: false), title: book.label.title
        )
    }
}
