internal import SwiftUI
#if canImport(UIKit)
internal import UIKit
#endif

internal import DesignSystem
internal import StoryArcCore

/// The size a home screen draws an app icon at.
///
/// `settings-and-about` asks each option to be shown "as the icon it actually is, at the size
/// a home screen draws it" — 60 points is that size on a phone. Fixed rather than scaled with
/// the reader's text: the requirement at the largest accessibility size is that the *names*
/// are readable and the tiles are still large enough to tell apart, and a tile that grew with
/// the text would push the name it exists beside off the row.
private let tileSide: CGFloat = 60

/// iOS's own icon corner, close enough that a tile reads as an app icon rather than as a
/// rounded square. `.rect(cornerRadius:style: .continuous)` is the squircle; the radius is
/// roughly 22.5% of the side, which is Apple's own ratio.
private let tileCorner: CGFloat = tileSide * 0.225

extension AppIconChoice {
    /// What the row calls this face.
    ///
    /// In the feature rather than on the type, for the reason `AppearanceMode`'s name lives in
    /// `DesignSystem`: a domain value does not know what a screen calls it. Android's
    /// `labelRes` is the same split.
    var localizedNameKey: LocalizedStringKey {
        switch self {
        case .ink: "appIcon.ink"
        case .paper: "appIcon.paper"
        case .bloom: "appIcon.bloom"
        case .arc: "appIcon.arc"
        case .mono: "appIcon.mono"
        }
    }
}

/// One face, drawn as the icon it is.
///
/// **Decorative to assistive technology.** `settings-and-about`: "the tile itself is
/// decorative to assistive technology, because the name is what identifies it". A tile
/// announced as an image would make every row read "image, Paper" and say nothing a blind
/// reader can act on.
private struct AppIconTile: View {
    @Environment(\.theme) private var theme
    let choice: AppIconChoice

    /// The face's own artwork, from the drawable copy the app ships beside each icon.
    ///
    /// **The app did not ship one at first, and a capture is what found that.** The first version
    /// drew
    /// `Image(choice.assetName)` and every tile came out blank — five empty rounded rectangles,
    /// which no test could have failed on, because a missing image is not an error in SwiftUI.
    /// `xcrun assetutil --info` on the built `Assets.car` says why: an `.appiconset` compiles
    /// to an *Icon Image*, and an icon asset is not fetchable by name at all. `UIImage(named:)`
    /// answers nothing either, `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` emits no
    /// loose file, and listing the generator's PNG as a second resource makes XcodeGen write a
    /// flattened path that does not build.
    ///
    /// **So each face is emitted twice**, both from one render at one inset: once as the
    /// `.appiconset` the platform installs, and once as an ordinary `.imageset` named by
    /// ``AppIconChoice/tileResourceName``. `scripts/brand-mark.swift` writes both, which is what
    /// keeps the tile a reader picks from drifting away from the icon they get. Verified in the
    /// built catalogue rather than by eye: `xcrun assetutil --info` reports all five as
    /// `AssetType: Image` at 180 px, where the `.appiconset`s are `Icon Image` and unfetchable.
    ///
    /// From the **main** bundle rather than this module's: the artwork belongs to the app
    /// target, which is where an app icon has to live.
    private var rendition: Image? {
        #if canImport(UIKit)
        UIImage(named: choice.tileResourceName).map(Image.init(uiImage:))
        #else
        // macOS carries this module only so the pure suites can run on the host, and nothing
        // there draws a chooser.
        nil
        #endif
    }

    var body: some View {
        Group {
            if let rendition {
                rendition.resizable()
            } else {
                // Not a placeholder mark — a plain surface. An icon this build cannot load is
                // a defect, and drawing something plausible in its place is how the blank
                // tiles above survived a screenshot.
                theme.palette.surfaceRaised
            }
        }
        .frame(width: tileSide, height: tileSide)
        .clipShape(.rect(cornerRadius: tileCorner, style: .continuous))
        .overlay {
            // A hairline, so Paper's off-white plate has an edge on a light background.
            // Without it the lightest face reads as a floating mark rather than a tile.
            RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                .strokeBorder(theme.palette.textSecondary.opacity(0.25), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// The five faces, and what pressing one does.
///
/// A section inside Appearance rather than a screen of its own, because that is what the spec
/// asks for by name: "it sits beside Appearance, because both answer *what does the app look
/// like*". A push would put a screen between the reader and the answer, and the settings
/// search reaches it either way through ``SettingsAnchor/appIcon``.
struct AppIconSettings: View {
    @Environment(\.theme) private var theme
    let store: AppIconStore

    var body: some View {
        Section {
            ForEach(AppIconChoice.allCases, id: \.self) { face in
                row(for: face)
            }
        } header: {
            Text("appIcon.title", bundle: .module)
        } footer: {
            // The refusal, where the section's own explanation would otherwise be. It
            // replaces rather than joins it: a reader who has just been told the change
            // failed does not need the general note underneath.
            //
            // `settings-and-about`: it "says the icon could not be changed and which one is
            // still in use". Both, in one sentence, because "it could not be changed" alone
            // leaves a reader guessing what they are now looking at.
            if store.refused != nil {
                Text(
                    "appIcon.refused \(Text(store.applied.localizedNameKey, bundle: .module))",
                    bundle: .module
                )
                .foregroundStyle(theme.palette.textPrimary)
            } else {
                Text("appIcon.note", bundle: .module)
            }
        }
        // The platform is the store, so this is where the two are reconciled: an icon can
        // change without this screen — a restore, a reinstall, an older build — and
        // `alternateIconName` is the only thing that knows.
        .onAppear { store.reconcile() }
    }

    /// One row: the tile, the name, whether it is in use, and whether it is the default.
    private func row(for face: AppIconChoice) -> some View {
        let isApplied = store.applied == face

        return Button { store.choose(face) } label: {
            // The tile beside the text, and the text allowed to wrap. At the largest
            // accessibility size the name is what has to stay readable in full, so it takes
            // the width and the row grows taller rather than truncating.
            HStack(spacing: StoryArcSpace.md) {
                AppIconTile(choice: face)
                VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                    Text(face.localizedNameKey, bundle: .module)
                        .foregroundStyle(theme.palette.textPrimary)
                    if face.isDefault {
                        Text("appIcon.default", bundle: .module)
                            .textRole(.footnote)
                            .foregroundStyle(theme.palette.textTertiary)
                    }
                }
                Spacer()
                if isApplied {
                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Announced "by name and by whether it is the one in use", and as one control rather
        // than as a tile followed by two pieces of text. `.isSelected` is what a screen
        // reader says "in use" with, so the state is not a second label to translate.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isApplied ? [.isButton, .isSelected] : .isButton)
    }
}
