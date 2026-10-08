public import Foundation

/// One line of the import preview, as a value the screen words in four languages.
///
/// `library-portability` / *The reader sees what will happen first*. The plan holds counts and
/// names; this orders them and drops the empty ones, so the screen is a `ForEach` over the list
/// and a test can assert what the reader is told without drawing anything. Android's
/// `ImportPreviewLine` is the same list in the same order.
public enum ImportPreviewLine: Sendable, Equatable {
    /// Hosts that gain a pinned certificate, and the source each arrived with. First, because it
    /// is a change to what the app trusts and not a change to what the reader owns.
    case certificatePins([CertificatePinNotice])

    case sourcesToAdd([String])
    case sourcesNeedingSignIn([String])
    case shelvesToAdd([String])

    /// Shelves on both sides, with how many members the import adds to each.
    case shelvesMerged([ImportedShelf])

    case progress(add: Int, merge: Int)
    case themes(Int)
    case covers(Int)
    case settingsChange

    /// The document holds nothing this device lacks.
    case nothingNew
}

public extension LibraryImportPlan {

    /// What the reader is told, in the order they are told it. Never empty.
    var previewLines: [ImportPreviewLine] {
        var lines: [ImportPreviewLine] = []
        if !certificatePinsToAdd.isEmpty { lines.append(.certificatePins(certificatePinsToAdd)) }
        if !sourcesToAdd.isEmpty { lines.append(.sourcesToAdd(sourcesToAdd)) }
        if !sourcesNeedingSignIn.isEmpty { lines.append(.sourcesNeedingSignIn(sourcesNeedingSignIn)) }
        if !shelvesToAdd.isEmpty { lines.append(.shelvesToAdd(shelvesToAdd)) }
        if !shelvesToMerge.isEmpty { lines.append(.shelvesMerged(shelvesToMerge)) }
        if progressToAdd + progressToMerge > 0 {
            lines.append(.progress(add: progressToAdd, merge: progressToMerge))
        }
        if themeEntriesToAdd > 0 { lines.append(.themes(themeEntriesToAdd)) }
        if coversToAdd > 0 { lines.append(.covers(coversToAdd)) }
        if settingsWillChange { lines.append(.settingsChange) }
        return lines.isEmpty ? [.nothingNew] : lines
    }
}
