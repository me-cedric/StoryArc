public import Foundation

/// One of the five faces of the mark a reader can put on the home screen.
///
/// `settings-and-about`: "faces of one mark, not different marks — a reader picking a
/// lighter tile is still holding StoryArc". The five are the ones
/// `scripts/brand-mark.swift` renders, and this type carries the *names* of what that
/// generator wrote rather than any geometry of its own: the asset is the deliverable, and
/// a second description of it here would be a second place to be wrong.
///
/// In the domain rather than in `SettingsFeature`, for the reason `AppearanceMode` is:
/// it is a *choice*, the mapping to a `UIImage` or an `<activity-alias>` is the
/// platform's business, and a value type is what both platforms' tests can assert
/// against without a device. Mirrored case for case by Android's `AppIconChoice` —
/// including the order, because that is the order the chooser draws them in.
///
/// **The platform is the store.** There is deliberately no entry for this in
/// `AppSettings`. iOS persists `alternateIconName` itself and Android persists a
/// component's enabled state itself, so a preference beside either one would be a second
/// answer to a question the platform already answers — and the spec asks the chooser to
/// show "what was applied", which is exactly the platform's answer and never a stored
/// intention. See `AppIconStore` on iOS and `AppIconAliases` on Android.
public enum AppIconChoice: String, CaseIterable, Sendable, Codable {
    /// The near-black plate the artwork leads with. What a fresh install draws.
    case ink
    /// The warm off-white plate, for a light home screen.
    case paper
    /// The pale lavender plate the artwork's third variant uses.
    case bloom
    /// The saturated violet plate. The loud one.
    case arc
    /// Ink's plate with the mark in a single ink — and the source of Android's
    /// `<monochrome>` layer, which is why it is a face rather than only a layer.
    case mono

    /// What a fresh install draws, and what "reset" returns to.
    ///
    /// `ink` and not merely "the first case": the default is a product decision, and a
    /// reorder of the chooser must not be able to change which icon a new reader gets.
    public static let `default`: AppIconChoice = .ink

    /// Whether this is the face the app ships with.
    ///
    /// `settings-and-about`: "the default is marked as the default, so a reader can find
    /// it without remembering which one it was".
    public var isDefault: Bool { self == Self.default }

    /// The `.appiconset` in the app's asset catalogue that holds this face.
    ///
    /// The primary set is called `AppIcon` and the alternates `AppIcon-<Face>` — the
    /// names `scripts/brand-mark.swift` writes, spelled here so a rename of either side
    /// fails a test rather than a home screen.
    public var assetName: String {
        isDefault ? "AppIcon" : "AppIcon-\(rawValue.capitalized)"
    }

    /// What `setAlternateIconName(_:)` takes: the alternate's name, or `nil` for the
    /// primary.
    ///
    /// `nil` is not "no icon" and not "unchanged" — it is UIKit's spelling of *the icon
    /// declared in the Info.plist*, which is why the default face maps to it rather than
    /// to `"AppIcon"`. Passing `"AppIcon"` here fails, because the primary set is not one
    /// of `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
    public var alternateIconName: String? { isDefault ? nil : assetName }

    /// The face a platform's own answer names.
    ///
    /// `alternateIconName` is the truth and a stored preference is not, so this is the
    /// direction that matters: iOS is asked what it is drawing and the answer is turned
    /// back into a face. An unrecognised name — an icon this build no longer ships, left
    /// behind by an update — resolves to the default rather than to nothing, because the
    /// icon a reader is looking at in that state *is* the primary one.
    public init(alternateIconName name: String?) {
        guard let name else { self = .default; return }
        self = Self.allCases.first { $0.alternateIconName == name } ?? .default
    }
}
