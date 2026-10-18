import DesignSystem
import StoryArcCore
import SwiftUI

/// The reader's look, kept per Mac beside the typography: the brightness and the light and dark pair the page
/// follows when the system changes appearance (`ebook-reader`, *Theme choice*, *Theme follows appearance*).
@MainActor
enum EpubLook {
    static let brightnessKey = "app.storyarc.mac.epubBrightness"
    static let followsKey = "app.storyarc.mac.epubFollowsAppearance"
    static let lightKey = "app.storyarc.mac.epubLightTheme"
    static let darkKey = "app.storyarc.mac.epubDarkTheme"

    /// 0.5 to 1; the page is dimmed by the difference.
    static var brightness: Double {
        get { UserDefaults.standard.object(forKey: brightnessKey) as? Double ?? 1 }
        set { UserDefaults.standard.set(min(1, max(0.5, newValue)), forKey: brightnessKey) }
    }

    static var follows: Bool {
        get { UserDefaults.standard.bool(forKey: followsKey) }
        set { UserDefaults.standard.set(newValue, forKey: followsKey) }
    }

    static var pair: (light: ThemePreset, dark: ThemePreset) {
        get {
            let light = UserDefaults.standard.string(forKey: lightKey).flatMap(ThemePreset.init) ?? .paper
            let dark = UserDefaults.standard.string(forKey: darkKey).flatMap(ThemePreset.init) ?? .focus
            return (light, dark)
        }
        set {
            UserDefaults.standard.set(newValue.light.rawValue, forKey: lightKey)
            UserDefaults.standard.set(newValue.dark.rawValue, forKey: darkKey)
        }
    }

    /// The preset for an appearance when the page follows it, else nil.
    static func preset(for scheme: ColorScheme) -> ThemePreset? {
        guard follows else { return nil }
        return scheme == .dark ? pair.dark : pair.light
    }

    /// A token's `#rrggbb` as a colour.
    static func color(hex: String) -> Color? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        return Color(red: red, green: green, blue: Double(value & 0xFF) / 255)
    }

    /// The darken filter the renderer takes, in percent, for a brightness.
    static func darken(_ brightness: Double) -> Int { Int(((1 - brightness) * 100).rounded()) }

    /// The swatch colours of a preset, from the design tokens.
    static func colours(of preset: ThemePreset) -> (background: Color, text: Color) {
        let axes = EpubReaderModel.axes(of: preset)
        let background = (axes["backgroundColor"] as? String).flatMap(color(hex:))
            ?? Color(nsColor: .textBackgroundColor)
        let text = (axes["textColor"] as? String).flatMap(color(hex:)) ?? Color(nsColor: .textColor)
        return (background, text)
    }
}

/// Reading themes as the spec draws them (`ebook-reader`, *The theme surface opens on the presets*, *Themes are
/// named, not numbered*): the six presets as swatches with a specimen in their own colours, the active one
/// selected and marked modified when the typography moved; one action, as prominent as the grid, opens the
/// axes; picking a preset applies it and closes the surface. Brightness and the appearance pair sit under the grid.
struct EpubThemeSurface: View {
    let model: EpubReaderModel
    let close: () -> Void
    @State private var showsAxes = false
    @State private var brightness = EpubLook.brightness
    @State private var follows = EpubLook.follows
    @State private var pair = EpubLook.pair

    var body: some View {
        if showsAxes {
            EpubTextPanel(model: model)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 10), count: 3), spacing: 10) {
                    ForEach(ThemePreset.allCases, id: \.self) { preset in swatch(preset) }
                }
                Button { showsAxes = true } label: {
                    Label("desktop.epub.text", systemImage: "textformat.size").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                LabeledContent("desktop.epub.brightness") {
                    Slider(value: $brightness, in: 0.5...1) { Text("desktop.epub.brightness") }
                        .labelsHidden()
                        .frame(width: 170)
                        .onChange(of: brightness) { _, value in EpubLook.brightness = value; model.apply(model.theme) }
                }
                Toggle("desktop.epub.followsAppearance", isOn: $follows)
                    .onChange(of: follows) { _, value in EpubLook.follows = value }
                if follows {
                    Picker("desktop.epub.lightTheme", selection: $pair.light) { presetRows }
                    Picker("desktop.epub.darkTheme", selection: $pair.dark) { presetRows }
                }
            }
            .onChange(of: pair.light) { EpubLook.pair = pair }
            .onChange(of: pair.dark) { EpubLook.pair = pair }
            .padding(16)
            .frame(width: 340)
        }
    }

    private var presetRows: some View {
        ForEach(ThemePreset.allCases, id: \.self) { Text($0.titleKey).tag($0) }
    }

    private func swatch(_ preset: ThemePreset) -> some View {
        let (background, text) = EpubLook.colours(of: preset)
        let isActive = model.theme == preset
        return Button {
            model.apply(preset)
            close()
        } label: {
            VStack(spacing: 4) {
                Text("desktop.epub.theme.specimen")
                    .font(.system(size: 26, weight: preset == .bold ? .heavy : .regular, design: .serif))
                    .foregroundStyle(text)
                Text(preset.titleKey).font(.caption).foregroundStyle(text)
                if isActive, EpubTypography.values != ThemeValues() {
                    Text("desktop.epub.theme.modified").font(.caption2).foregroundStyle(text.opacity(0.8))
                }
            }
            .frame(width: 96, height: 76)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isActive ? 3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(preset.titleKey))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// How far through a reflowable book the reader is, in a sentence (`ebook-reader`, *Progress display*): the
/// share of the book and what is left of the chapter, never a page number, since pages move with typography.
enum EpubProgressLine {
    static func text(total: Double, chapter: Double) -> String {
        let read = Int((min(1, max(0, total)) * 100).rounded())
        let left = Int(((1 - min(1, max(0, chapter))) * 100).rounded())
        return String(localized: "desktop.epub.progress \(read) \(left)", locale: .storyArc)
    }
}
