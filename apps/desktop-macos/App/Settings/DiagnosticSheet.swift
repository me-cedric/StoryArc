import SwiftUI

/// One built export, identified so a sheet can present it.
struct DiagnosticText: Identifiable {
    let id = UUID()
    let text: String
}

/// The diagnostic shown in full before it is saved, then the save panel (task 3.14).
///
/// `desktop-experience`, *Saving the diagnostic*: shown, then a save dialog, then a file. A
/// cancelled save closes the sheet and the text goes with it. A place that cannot be written
/// is named in an alert that offers another place.
struct DiagnosticSheet: View {
    let text: String
    var exporter = DiagnosticExporter()
    @Environment(\.dismiss) private var dismiss
    @State private var failedPlace: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetTitle(title: "desktop.diagnostic.title")
            Text("desktop.diagnostic.redacted")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            ScrollView {
                Text(verbatim: text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .padding(20)
            .accessibilityLabel(Text("desktop.diagnostic.title"))
            SheetButtons(
                primary: "desktop.diagnostic.save", isPrimaryEnabled: true,
                onCancel: { dismiss() }, onPrimary: { Task { await save() } }
            )
        }
        .frame(width: 560, height: 520)
        .alert(
            Text("desktop.diagnostic.failed \(failedPlace ?? "")"),
            isPresented: Binding(get: { failedPlace != nil }, set: { if !$0 { failedPlace = nil } })
        ) {
            Button { failedPlace = nil; Task { await save() } } label: { Text("desktop.diagnostic.another") }
            Button(role: .cancel) { failedPlace = nil } label: { Text("desktop.sheet.cancel") }
        } message: {
            Text("desktop.diagnostic.failed.body")
        }
    }

    private func save() async {
        switch await exporter.export(text) {
        case .saved, .cancelled: dismiss()
        case let .failed(place): failedPlace = place
        }
    }
}
