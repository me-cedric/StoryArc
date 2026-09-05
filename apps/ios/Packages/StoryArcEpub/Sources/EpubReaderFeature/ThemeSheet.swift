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
    @Environment(\.dynamicTypeSize) private var typeSize

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

    /// How many preset cards sit in a row at a given text size.
    ///
    /// A function rather than an expression inside the grid, so a host test can ask it. There
    /// is no simulator in this repository's unit loop, and the defect this encodes — *Original*
    /// wrapping to `Origi-` over `nal` at `AccessibilityXXXL` — is invisible to every test that
    /// reads source text rather than pixels. The arithmetic is assertable even where the
    /// rendering is not.
    static func presetColumns(for typeSize: DynamicTypeSize) -> Int {
        typeSize.isAccessibilitySize ? 1 : 3
    }

    /// Three by two, each card in its own colours — and one column at the accessibility sizes.
    ///
    /// `ebook-reader`: the grid previews "each preset in its own colours — six
    /// samples, not six labels". A swatch that took the app's palette would be six
    /// identical cards with different words on them.
    ///
    /// **The column count is not fixed, and it used to be.** Three columns leave a card about
    /// 170 pt wide on a 402 pt phone, which holds every preset's name at the ordinary text
    /// sizes and holds none of them at the accessibility ones: photographed at
    /// `AccessibilityXXXL` on 2026-09-05, *Original* wrapped mid-word and drew as `Origi-`
    /// over `nal`. A card is the one control in the app whose label may not shrink to fit —
    /// the whole point of the grid is that each name is drawn in its own typeface at its own
    /// weight, so shrinking it would be showing the reader the wrong typeface.
    ///
    /// One column rather than two at those sizes, because two still leaves ~170 pt and the
    /// name needs about 250 pt: two columns would move the wrap without preventing it. Six
    /// cards in one column is a longer scroll, which is the trade the accessibility sizes
    /// make everywhere else in this app.
    ///
    /// The neighbouring `PageColourSection` grids use `.adaptive(minimum:)` for the same job,
    /// and this one cannot: a swatch is square and interchangeable, so any number per row is
    /// as good as any other, while these cards must be *equal* width or the samples stop
    /// being comparable — which is what a fixed count gives and `.adaptive` does not.
    private var presets: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.presets", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                // The trait, not `textRole`, is what lets VoiceOver jump section to section.
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(spacing: StoryArcSpace.sm),
                    count: Self.presetColumns(for: typeSize)
                ),
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
