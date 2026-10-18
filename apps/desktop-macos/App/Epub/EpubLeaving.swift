import AppKit
import SwiftUI

extension View {
    /// Asks before a link leaves the book, naming the host it goes to (`ebook-reader`, *Following a link out of
    /// the publication*): the reader leaves on a publication's say-so, so the system browser opens only on a yes.
    func leavingConfirmation(_ model: EpubReaderModel) -> some View {
        confirmationDialog(
            Text("desktop.epub.leave.title \(model.leaving?.host() ?? "")"),
            isPresented: Binding(get: { model.leaving != nil }, set: { if !$0 { model.leaving = nil } }),
            titleVisibility: .visible,
            presenting: model.leaving
        ) { url in
            Button { EpubLinkOpener.open(url) } label: { Text("desktop.epub.leave.open") }
            Button(role: .cancel) { model.leaving = nil } label: { Text("desktop.epub.leave.cancel") }
        } message: { url in
            Text(url.absoluteString)
        }
    }
}
