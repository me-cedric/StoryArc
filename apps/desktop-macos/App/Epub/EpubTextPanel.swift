import DesignSystem
import StoryArcCore
import SwiftUI

/// The second depth of the theme surface: the reader's own typography over the preset (`ebook-reader`,
/// *One sheet, two depths*, *Typography controls*, *An axis is inert while publisher styles are on*).
///
/// Each change goes to the page at once. Under *Original* the publisher's stylesheet is in force, so the axes it
/// governs are shown disabled with the reason beside them rather than hidden.
struct EpubTextPanel: View {
    let model: EpubReaderModel
    @State private var values = EpubTypography.values
    @State private var scrolls = EpubTypography.scrolls

    var body: some View {
        Form {
            Section {
                LabeledContent("desktop.epub.text.size") {
                    HStack {
                        Button { change { $0.fontSize = $0.fontSize.previous } } label: {
                            Label("desktop.epub.text.smaller", systemImage: "textformat.size.smaller")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(values.fontSize == FontSizeStep.allCases.first)
                        Text(values.fontSize.fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(minWidth: 44)
                        Button { change { $0.fontSize = $0.fontSize.next } } label: {
                            Label("desktop.epub.text.larger", systemImage: "textformat.size.larger")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(values.fontSize == FontSizeStep.allCases.last)
                    }
                }
                Picker("desktop.epub.text.typeface", selection: binding(\.typeface)) {
                    ForEach(EpubTypography.typefaces, id: \.self) { typeface in
                        Text(Self.titleKey(of: typeface)).tag(typeface)
                    }
                }
                Toggle("desktop.epub.text.bold", isOn: binding(\.isBold))
                slider("desktop.epub.text.margins", \.pageMargins, axis: .margins)
            }
            Section {
                slider("desktop.epub.text.lineSpacing", \.lineHeight, axis: .lineSpacing)
                slider("desktop.epub.text.paragraphSpacing", \.paragraphSpacing, axis: .paragraphSpacing)
                Picker("desktop.epub.text.alignment", selection: binding(\.textAlignment)) {
                    Text("desktop.epub.text.alignment.publisher").tag(ReaderTextAlignment.publisher)
                    Text("desktop.epub.text.alignment.left").tag(ReaderTextAlignment.left)
                    Text("desktop.epub.text.alignment.justified").tag(ReaderTextAlignment.justified)
                }
                Toggle("desktop.epub.text.hyphenation", isOn: binding(\.isHyphenated))
            } footer: {
                if model.theme.keepsPublisherStyles {
                    Text("desktop.epub.text.publisherStyles").foregroundStyle(.secondary)
                }
            }
            .disabled(model.theme.keepsPublisherStyles)
            Section {
                Toggle("desktop.epub.text.scroll", isOn: Binding(get: { scrolls }, set: { scrolls = $0; send() }))
                Button("desktop.epub.text.reset") {
                    values = ThemeValues()
                    send()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
    }

    private func slider(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<ThemeValues, Double>, axis: ThemeAxis
    ) -> some View {
        let range = axis.sliderRange ?? 0...1
        return LabeledContent(title) {
            Slider(value: binding(path), in: range, step: axis.step ?? 0.1) { Text(title) }
                .labelsHidden()
                .frame(width: 150)
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<ThemeValues, Value>) -> Binding<Value> {
        Binding(get: { values[keyPath: path] }, set: { value in change { $0[keyPath: path] = value } })
    }

    private func change(_ edit: (inout ThemeValues) -> Void) {
        edit(&values)
        send()
    }

    private func send() { model.apply(values, scroll: scrolls) }

    static func titleKey(of typeface: ReaderTypeface) -> LocalizedStringKey {
        switch typeface {
        case .publisher: "desktop.epub.text.typeface.publisher"
        case .serif: "desktop.epub.text.typeface.serif"
        case .sans: "desktop.epub.text.typeface.sans"
        case .literata: "desktop.epub.text.typeface.literata"
        case .sourceSerif: "desktop.epub.text.typeface.sourceSerif"
        case .ebGaramond: "desktop.epub.text.typeface.ebGaramond"
        case .bitter: "desktop.epub.text.typeface.bitter"
        case .atkinsonHyperlegible: "desktop.epub.text.typeface.atkinson"
        }
    }
}

/// The publication's table of contents, as a menu that goes to a chapter with a way back (`ebook-reader`,
/// *Table of contents*, *Moving somewhere else in a reflowable publication*).
struct EpubContentsMenu: View {
    let model: EpubReaderModel

    var body: some View {
        Menu {
            if model.contents.isEmpty {
                Text("desktop.epub.contents.none")
            }
            ForEach(Array(model.contents.enumerated()), id: \.offset) { _, link in
                Button(link.title ?? link.href) { model.go(to: EpubReaderModel.locator(for: link)) }
            }
        } label: {
            Label("desktop.epub.contents", systemImage: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("desktop.epub.contents"))
    }
}
