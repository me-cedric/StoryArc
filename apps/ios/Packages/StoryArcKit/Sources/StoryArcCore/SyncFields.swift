public import Foundation

/// The settings, field by field, as a sync merges them.
///
/// `library-sync` task 3.5. The names are the document's own keys, so the moments the document
/// carries line up with the fields they date. Android also has `turnPagesWithVolumeButtons`,
/// which this platform cannot express and so never merges: the field keeps each device's own
/// value. The sync place is not here and never travels.
public enum SettingsStamps {

    static var fields: [SyncField<DocumentSettings>] {
        [
            SyncField("appearance", \.appearance),
            SyncField("language", \.language),
            SyncField("turnPagesByTappingTheEdges", \.turnPagesByTappingTheEdges),
            SyncField("linkReadingThemeToAppearance", \.linkReadingThemeToAppearance),
            SyncField("lightReadingTheme", \.lightReadingTheme),
            SyncField("darkReadingTheme", \.darkReadingTheme),
            SyncField("downloadOverWifiOnly", \.downloadOverWifiOnly),
            SyncField("maximumDownloadBytes", \.maximumDownloadBytes),
            SyncField("removeDownloadsAfterFinishing", \.removeDownloadsAfterFinishing),
        ]
    }

    /// The fields the reader changed between two values, by name.
    public static func changed(from before: AppSettings, to after: AppSettings) -> [String] {
        ChangeStamps.changed(fields, DocumentSettings(before), DocumentSettings(after))
    }

    /// This device's settings merged with the document's, newer field wins.
    public static func merging(
        _ local: AppSettings,
        stamps localStamps: [String: Date],
        with remote: DocumentSettings,
        device: String
    ) -> StampedValue<AppSettings> {
        let merged = ChangeStamps.merging(
            fields, default: DocumentSettings(), local: DocumentSettings(local),
            localStamps: localStamps, remote: remote, remoteStamps: remote.changed ?? [:],
            device: device
        )
        return StampedValue(value: merged.value.settings(keeping: local), changedAt: merged.changedAt)
    }
}

/// The reading themes, field by field, as a sync merges them.
///
/// A field's moment is filed under `scope/shelf|field`: the entry the document already names (an
/// entry with no shelf is a scope's default), then the field. The custom colour slot is one more
/// field, ``customPalette``. Android's `ThemeStamps` files them the same way.
public enum ThemeStamps {

    public static let customPalette = "customPalette"

    static var fields: [SyncField<DocumentShelfSettings>] {
        [
            SyncField("theme.preset", \.theme.preset),
            SyncField("theme.deviations", \.theme.deviations),
            SyncField("theme.custom", \.theme.custom),
            SyncField("values.typeface", \.values.typeface),
            SyncField("values.fontSizePercent", \.values.fontSizePercent),
            SyncField("values.isBold", \.values.isBold),
            SyncField("values.isHyphenated", \.values.isHyphenated),
            SyncField("values.lineHeight", \.values.lineHeight),
            SyncField("values.letterSpacing", \.values.letterSpacing),
            SyncField("values.wordSpacing", \.values.wordSpacing),
            SyncField("values.paragraphSpacing", \.values.paragraphSpacing),
            SyncField("values.pageMargins", \.values.pageMargins),
            SyncField("values.textAlignment", \.values.textAlignment),
            SyncField("transition", \.transition),
            SyncField("scrollAxis", \.scrollAxis),
            SyncField("readingDirection", \.readingDirection),
            SyncField("adjustments", \.adjustments),
            SyncField("offsetsSpreads", \.offsetsSpreads),
            SyncField("showsPageSeparator", \.showsPageSeparator),
            SyncField("fit", \.fit),
        ]
    }

    private static var palette: SyncField<ReaderPalette?> {
        SyncField(customPalette, same: ==, take: { $0 = $1 })
    }

    /// The entry a field's moment is filed under.
    public static func entry(_ scope: String, _ shelf: String?) -> String { "\(scope)/\(shelf ?? "")" }

    private static func byEntry(_ memory: ShelfMemory) -> [String: ShelfMemory.Entry] {
        Dictionary(
            memory.entries.map { (entry($0.scope.rawValue, $0.shelf), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The fields the reader changed between two memories, by their filed names.
    ///
    /// An entry that is not there reads as the defaults, so creating one stamps only the fields
    /// that differ from them, and removing one stamps the fields it had changed.
    public static func changed(from before: ShelfMemory, to after: ShelfMemory) -> [String] {
        let old = byEntry(before)
        let new = byEntry(after)
        let fallback = DocumentShelfSettings(ShelfSettings())
        var names = Set(old.keys).union(new.keys).sorted().flatMap { name in
            ChangeStamps.changed(
                fields,
                old[name].map { DocumentShelfSettings($0.settings) } ?? fallback,
                new[name].map { DocumentShelfSettings($0.settings) } ?? fallback,
                prefix: "\(name)|"
            )
        }
        if before.customPalette != after.customPalette { names.append(customPalette) }
        return names
    }

    /// This device's themes merged with the document's, newer field wins.
    ///
    /// An entry only the document has arrives whole, unless this device removed it later: then
    /// its fields are merged against the defaults the removal left.
    public static func merging(
        _ local: ShelfMemory,
        stamps localStamps: [String: Date],
        with remote: DocumentThemes,
        device: String
    ) -> StampedValue<ShelfMemory> {
        let mine = byEntry(local)
        var theirs: [String: ShelfMemory.Entry] = [:]
        for arriving in remote.entries {
            guard let scope = ThemeScope(rawValue: arriving.scope) else { continue }
            theirs[entry(arriving.scope, arriving.shelf)] = ShelfMemory.Entry(
                scope: scope, shelf: arriving.shelf, settings: arriving.settings.settings
            )
        }
        let arrivingStamps = ChangeStamps.moments(remote.changed)
        let fallback = DocumentShelfSettings(ShelfSettings())

        var memory = ShelfMemory()
        var stamps: [String: Date] = [:]
        for name in Set(mine.keys).union(theirs.keys).sorted() {
            let prefix = "\(name)|"
            let held = mine[name]
            let removedHere = localStamps.keys.contains { $0.hasPrefix(prefix) }
            let settings: ShelfSettings
            if let held, theirs[name] == nil {
                settings = held.settings
                stamps.merge(localStamps.filter { $0.key.hasPrefix(prefix) }) { _, new in new }
            } else if let arriving = theirs[name], held == nil, !removedHere {
                settings = arriving.settings
                stamps.merge(arrivingStamps.filter { $0.key.hasPrefix(prefix) }) { _, new in new }
            } else {
                let merged = ChangeStamps.merging(
                    fields, default: fallback,
                    local: held.map { DocumentShelfSettings($0.settings) } ?? fallback,
                    localStamps: localStamps,
                    remote: DocumentShelfSettings(theirs[name]?.settings ?? ShelfSettings()),
                    remoteStamps: remote.changed ?? [:], device: device
                ) { prefix + $0 }
                settings = merged.value.settings
                stamps.merge(merged.changedAt) { _, new in new }
            }
            guard let shape = held ?? theirs[name] else { continue }
            memory = memory.recording(ShelfMemory.Entry(scope: shape.scope, shelf: shape.shelf, settings: settings))
        }
        let colours = ChangeStamps.merging(
            [palette], default: nil, local: local.customPalette, localStamps: localStamps,
            remote: remote.customPalette, remoteStamps: remote.changed ?? [:], device: device
        )
        stamps.merge(colours.changedAt) { _, new in new }
        memory.customPalette = colours.value
        return StampedValue(value: memory, changedAt: stamps)
    }
}
