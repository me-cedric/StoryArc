import AppKit

/// What a quit owes a download in progress, before anything else runs.
///
/// `desktop-experience`, *A download in progress*: the app says before quitting that the
/// download will pause and resume at the next launch, and quits when the reader agrees. The
/// partial file is kept: the queue pauses rather than cancels, and `MacDownloads` remembers
/// what it paused so the next launch resumes exactly that. A quit with nothing transferring
/// asks nothing. Its parts are closures so the rule is a test (`DownloadsQuitTests`).
@MainActor
struct MacQuit {
    let isTransferring: Bool
    let confirm: @MainActor () -> Bool
    let pauseForQuit: () -> Void

    init(isTransferring: Bool, confirm: @escaping @MainActor () -> Bool, pauseForQuit: @escaping () -> Void) {
        self.isTransferring = isTransferring
        self.confirm = confirm
        self.pauseForQuit = pauseForQuit
    }

    init(downloads: MacDownloads?, confirm: @escaping @MainActor () -> Bool = MacQuit.askAboutDownloads) {
        self.init(
            isTransferring: downloads?.isTransferring ?? false, confirm: confirm,
            pauseForQuit: { downloads?.pauseForQuit() }
        )
    }

    /// Whether the quit goes ahead. When it does, every transfer is paused for the next launch.
    func shouldQuit() -> Bool {
        guard isTransferring else { return true }
        guard confirm() else { return false }
        pauseForQuit()
        return true
    }

    /// The system's own alert: what happens, Quit, and Cancel.
    static func askAboutDownloads() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "desktop.quit.download.title")
        alert.informativeText = String(localized: "desktop.quit.download.body")
        alert.addButton(withTitle: String(localized: "desktop.quit.download.quit"))
        alert.addButton(withTitle: String(localized: "desktop.sheet.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
