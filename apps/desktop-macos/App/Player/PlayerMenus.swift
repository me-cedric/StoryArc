import Playback
import StoryArcCore
import SwiftUI

/// The sleep timer, offered wherever the session is controlled (`audio-playback`, *Sleep timer*): off, five to
/// sixty minutes, or the end of the chapter where the session has chapters with a length. The label says what
/// is left, so a running timer is visible without opening the menu.
struct SleepMenu: View {
    let centre: PlayerCentre

    var body: some View {
        Menu {
            Button("desktop.player.sleep.off") { centre.setSleepTimer(nil) }
                .disabled(centre.sleep == nil)
            ForEach(SleepTimer.durations, id: \.self) { duration in
                Button("desktop.player.sleep.minutes \(Int(duration / 60))") { centre.setSleepTimer(.after(duration)) }
            }
            if centre.canSleepAtEndOfChapter {
                Button("desktop.player.sleep.endOfChapter") { centre.setSleepTimer(.endOfChapter) }
            }
        } label: {
            if let sleep = centre.sleep {
                Label("desktop.player.sleep.remaining \(Self.clock(sleep.remaining))", systemImage: "moon.zzz.fill")
            } else {
                Label("desktop.player.sleep", systemImage: "moon.zzz")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("desktop.player.sleep"))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}

/// The chapters, each with its length and whether it is heard, in progress or ahead (`audio-playback`,
/// *Chapters*), the phones' `ChapterProgress` rule.
struct ChaptersMenu: View {
    let centre: PlayerCentre

    var body: some View {
        Menu {
            ForEach(centre.parts) { part in
                let mark = ChapterProgress.mark(
                    of: part.index, reached: centre.place.partIndex, isFinished: centre.hasReachedTheEnd
                )
                Button { centre.play(part: part.index) } label: {
                    Label(Self.row(part, mark: mark, offset: centre.place.offset), systemImage: mark.glyph)
                }
            }
        } label: {
            Label("desktop.player.chapters", systemImage: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("desktop.player.chapters"))
    }

    /// "Chapter 3 · 12:40" for a chapter ahead, "Chapter 3 · 4:10 left" for the one in progress.
    static func row(_ part: PlaybackPart, mark: ChapterMark, offset: TimeInterval) -> String {
        let name = part.title ?? PlayerWindow.partName(part.index)
        if let left = ChapterProgress.remainder(ofChapterLasting: part.duration, mark: mark, at: offset) {
            let remaining = String(localized: "desktop.player.chapter.left \(SleepMenu.clock(left))", locale: .storyArc)
            return name + " · " + remaining
        }
        guard let duration = part.duration else { return name }
        return name + " · " + SleepMenu.clock(duration)
    }
}
