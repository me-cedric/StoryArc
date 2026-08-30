internal import Dispatch

internal import StoryArcCore

/// What the system says about memory, as it changes.
///
/// `comic-reader`: "prefetch depth shrinks under memory pressure rather than the app
/// being terminated". Something has to *tell* the reader, and on Darwin that is a
/// dispatch memory-pressure source rather than
/// `UIApplication.didReceiveMemoryWarningNotification`: the notification only ever says
/// there is trouble and never says it is over, so a reader who met one warning early in
/// a book would read the rest of it one page at a time. The source reports `.normal`
/// again, which is what lets the window grow back.
///
/// A stream rather than a delegate, so the reader can consume it with the same `.task`
/// lifetime as everything else it watches: leaving the reader cancels the task, which
/// cancels the source.
///
/// Android has no equivalent "all clear" — see `ReaderScreen`'s trim callbacks for what
/// it does instead.
enum MemoryPressureSource {
    static func pressures() -> AsyncStream<MemoryPressure> {
        AsyncStream { continuation in
            // Not on the main queue: the handler runs while the system is under pressure,
            // and the reader's job at that moment is to give memory back rather than to
            // wait for a frame.
            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.normal, .warning, .critical],
                queue: .global(qos: .utility)
            )
            source.setEventHandler {
                continuation.yield(pressure(of: source.data))
            }
            continuation.onTermination = { _ in source.cancel() }
            source.activate()
        }
    }

    /// The worst thing the event says, because an event can carry more than one flag and
    /// the reader should answer the most serious of them.
    private static func pressure(
        of event: DispatchSource.MemoryPressureEvent
    ) -> MemoryPressure {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return .normal
    }
}
