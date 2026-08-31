public import SwiftUI

internal import DesignSystem
internal import UIKit

public import StoryArcCore

/// The reading-theme sheet.
///
/// `ebook-reader` and `reading-themes` between them ask for a preset grid, a
/// stepped font size with a visible position, and — the part that is easy to skip —
/// an axis that cannot reach the page shown "unavailable with a one-line reason and
/// a single action that turns publisher styles off". Not hidden, and not a live
/// control that does nothing.
///
/// Custom backgrounds are Phase 3.7 and are not here yet. Everything else the
/// spec describes at both levels is.
struct ThemeSheet: View {
    @Environment(\.theme) var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let model: EpubReaderModel

    /// Words from where the reader is, read once when the sheet opens. Empty until the
    /// resource comes back, and empty for good on a publication it cannot be read from —
    /// the preview shows its sample paragraph in both cases.
    @State private var excerpt = ""

    /// Whether level two — the axes — is on screen.
    @State private var isCustomising = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    // First, because it is the thing every card below it previews.
                    ThemePreview(
                        readingTheme: model.theme,
                        values: model.values,
                        title: model.chapterTitle,
                        excerpt: excerpt
                    )
                    presets
                    customise
                }
                .padding(StoryArcSpace.gutter)
            }
            // Once, on open. The reader's position does not move while the sheet is up,
            // and re-reading the resource on every slider step would put a disk read
            // inside a drag.
            .task { excerpt = await model.previewExcerpt() }
            // No background of our own. A sheet on iOS 26 is already presented
            // on Liquid Glass, and `native-experience` wants it "left untinted so
            // it picks up the page beneath it" — an opaque fill here is the one
            // thing that would prevent that. The system's material also carries
            // its own Reduce-Transparency fallback, so declaring a second one
            // would only be able to disagree with it.
            // Inline, not a large title. A large title puts the sheet's name on its own
            // line under the toolbar, which costs a reader about 60 points of the page
            // they came here to adjust — on a sheet that is already only half the screen.
            .navigationTitle(Text("theme.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("theme.done", bundle: .module) }
                }
            }
        }
        // Level two, as a second sheet from the first.
        //
        // Sheet-on-sheet is idiomatic on iOS and the platform animates it as a stack.
        // Android does not do this: `design.md` records why, and the short version is that
        // predictive back is a component-level contract there and two stacked modal sheets
        // give the gesture two competing dismiss targets and no correct preview.
        .sheet(isPresented: $isCustomising) {
            ThemeAxesSheet(model: model, excerpt: excerpt)
        }
    }

    /// The one action on level one, and the reason level one is only presets.
    ///
    /// `ebook-reader`: "one action, given equal prominence to the grid, opens the axes".
    /// Full-width and bordered-prominent, so it reads as the grid's peer rather than as a
    /// footnote under it — a reader who came to nudge line spacing has to be able to see
    /// where that lives without having learnt it first.
    private var customise: some View {
        Button { isCustomising = true } label: {
            Label {
                Text("theme.customise", bundle: .module)
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// Three by two, each card in its own colours.
    ///
    /// `ebook-reader`: the grid previews "each preset in its own colours — six
    /// samples, not six labels". A swatch that took the app's palette would be six
    /// identical cards with different words on them.
    private var presets: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.presets", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                // The trait, not `textRole`, is what lets VoiceOver jump section to section.
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: Array(repeating: GridItem(spacing: StoryArcSpace.sm), count: 3),
                spacing: StoryArcSpace.sm
            ) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    PresetCard(
                        preset: preset,
                        isActive: model.theme.preset == preset && !model.theme.isCustom,
                        isModified: model.theme.preset == preset && model.theme.isModified
                    ) {
                        model.adopt(preset)
                        // `ebook-reader`: "picking a preset applies it and leaves the surface,
                        // because that was the whole errand". A sheet that stayed up over the
                        // change would put the reader's own decision behind their own choice.
                        dismiss()
                    }
                }
                // The seventh slot, present only once the reader has made one.
                // `reading-themes` puts it "alongside the six presets rather than
                // overwriting one", so it is a seventh card and not a replaced one.
                if let custom = model.theme.custom {
                    CustomCard(palette: custom, typeface: model.values.typeface) {
                        model.adoptColours(custom)
                    }
                }
            }
        }
    }

}
