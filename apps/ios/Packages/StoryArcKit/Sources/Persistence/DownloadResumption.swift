public import Foundation

public import StoryArcCore

extension DownloadStore {
    /// What the system needs to carry on a transfer this app interrupted.
    ///
    /// `offline-downloads` asks an interrupted download to resume "from where it stopped".
    /// **The two platforms reach that differently, and the platform forces the difference.**
    /// Android holds the fetched bytes in a partial file of its own and asks the server for
    /// the rest with a `Range` header. Here the transfer belongs to a background
    /// `URLSession` — which is what lets it continue while the app is not running — and the
    /// bytes it has fetched live where this process cannot reach them. What the system
    /// offers instead is `cancel(byProducingResumeData:)`: an opaque token that
    /// `downloadTask(withResumeData:)` turns back into the same transfer, ranged request and
    /// all. This is where that token is kept, so it outlives the process the way the record
    /// beside it does.
    ///
    /// Derived from ``location(of:)`` rather than from the identifier again, so the token
    /// lands in the download's own directory and ``remove(_:)`` takes it with everything
    /// else. A reader who removes a download and is left paying for the makings of half of
    /// one has been told the bytes are gone when they are not.
    ///
    /// Its own file because ``DownloadStore`` is at the 400-line cap this project enforces.
    public func resumeData(of download: Download) -> URL {
        location(of: download)
            .deletingLastPathComponent()
            .appending(path: "resume.data")
    }
}
