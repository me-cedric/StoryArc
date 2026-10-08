import SwiftUI
import WidgetKit

import StoryArcCore

/// The home-screen widget: the book being read, its cover and how far the reader got.
///
/// `native-experience` names widgets among the system affordances the app uses. ADR-0011 sets
/// the one rule this follows: the widget reads the ``ReadingSnapshot`` the app wrote into the
/// App Group container, and nothing else. Android's `ReadingWidget` is the other platform's
/// widget over its own snapshot.
@main
struct StoryArcWidgets: WidgetBundle {
    var body: some Widget {
        ReadingWidget()
    }
}

struct ReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ReadingSnapshot.widgetKind, provider: ReadingTimeline()) { entry in
            ReadingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.name"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ReadingEntry: TimelineEntry {
    let date: Date
    let snapshot: ReadingSnapshot?
    let cover: URL?
}

/// One entry, and no schedule: the app asks for a redraw when the snapshot changes, and
/// nothing else changes what the widget shows.
struct ReadingTimeline: TimelineProvider {

    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(date: .now, snapshot: nil, cover: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> ReadingEntry {
        let store = ReadingSnapshotStore.shared()
        let snapshot = store?.read()
        return ReadingEntry(
            date: .now,
            snapshot: snapshot,
            cover: snapshot.flatMap { store?.cover(of: $0) }
        )
    }
}
