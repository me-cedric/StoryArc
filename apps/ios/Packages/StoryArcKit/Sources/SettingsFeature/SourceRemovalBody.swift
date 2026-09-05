internal import SwiftUI

internal import Persistence
internal import StoryArcCore

/// The sentence a removal confirmation shows, in words.
///
/// ``StoryArcCore/SourceRemovalWording`` decides *which* sentence and with what figures; this is
/// the one place that turns the decision into a `Text`, so the detail screen's dialog and the
/// list's swipe cannot describe the same source differently. Both used to say that no files
/// are deleted, which was false for any source holding a download and photographed as such on
/// 2026-09-05.
///
/// The bytes go through ``Persistence/DownloadStore/formatted(_:)``, the same helper as the
/// *Downloaded* field one screen up, so the dialog can never name a size spelled differently
/// from the row the reader read it on — the defect that helper exists to stop.
enum SourceRemovalBody {
    static func text(for wording: SourceRemovalWording) -> Text {
        switch wording {
        case let .titlesOnly(titleCount):
            return Text("sources.remove.body \(titleCount)", bundle: .module)
        case let .titlesAndDownloads(titleCount, downloadCount, downloadedBytes):
            // The two counts are inflected fragments resolved first, because a catalogue entry
            // can inflect one argument and not two; the sentence then takes them as words. The
            // titles fragment is the one the detail field and the list row already draw.
            let titles = String(localized: "sources.detail \(titleCount)", bundle: .module, locale: .storyArc)
            let downloads = String(
                localized: "sources.remove.downloads \(downloadCount)", bundle: .module, locale: .storyArc
            )
            let space = DownloadStore.formatted(downloadedBytes)
            return Text("sources.remove.bodyWithDownloads \(titles) \(downloads) \(space)", bundle: .module)
        }
    }
}
