/// Which sentence a removal confirmation shows, and the figures it carries.
///
/// `sources`, *Removing a source*: the app "states how many downloaded files and how much disk
/// space will be freed before asking for confirmation", and on confirmation removes the source
/// "and its downloads". The sentence the reader confirmed against said the opposite — *"No files
/// on your device are deleted, and nothing was downloaded"* — which is true for a source with no
/// downloads and a false promise for one with 400 MB of them, while both apps deleted the files
/// anyway: `StoryArcAppActions.removeSource` and Android's `SettingsHost` call `removeDownloads`
/// before the model forgets the source. The space freed was stated nowhere before the tap.
///
/// One rule for both dialogs on both platforms, with no words in it. The wording lives in the
/// feature that draws it, in four languages; this is which of the two sentences to draw and what
/// to put in the holes — the same split ``SourceFailure`` makes. Decided by the count of finished
/// downloads rather than by their bytes: a finished download that weighs nothing is still a file
/// the removal deletes, and a sentence saying nothing is deleted would be wrong about it.
/// Android's `SourceRemovalWording` answers the same way, and its test mirrors this one's.
///
/// Two states and not three sentences, and each state is one sentence, because a
/// `confirmationDialog` at `AccessibilityXXXL` shows about seven short lines and does not scroll
/// — photographed on 2026-09-05, with a `-scrolled` twin proving the rest could not be reached.
/// The retention sentence is a footer on the screen beneath for the same reason.
public enum SourceRemovalWording: Sendable, Equatable {
    /// Nothing of this source is on disk. The removal frees no bytes, so the sentence names only
    /// what leaves the library.
    case titlesOnly(titleCount: Int)

    /// Some of it is. The sentence names the files the removal deletes and the space they take,
    /// figures first, so that a frame that runs out of room loses words rather than numbers.
    case titlesAndDownloads(titleCount: Int, downloadCount: Int, downloadedBytes: Int64)

    /// The sentence for a source that holds `titleCount` publications, `downloadCount` of them
    /// finished on disk, weighing `downloadedBytes` between them.
    public static func of(titleCount: Int, downloadCount: Int, downloadedBytes: Int64) -> SourceRemovalWording {
        guard downloadCount > 0 else { return .titlesOnly(titleCount: titleCount) }
        return .titlesAndDownloads(
            titleCount: titleCount,
            downloadCount: downloadCount,
            downloadedBytes: downloadedBytes
        )
    }

    /// The sentence for a source as its detail screen already knows it.
    ///
    /// ``SourceDiagnosis`` counts the finished downloads and their bytes for the *Downloaded*
    /// field; taking them from there is what keeps the dialog from naming a figure the row did
    /// not. The list's swipe has no detail screen open and asks the same question the same way.
    public static func of(_ diagnosis: SourceDiagnosis) -> SourceRemovalWording {
        of(
            titleCount: diagnosis.itemCount,
            downloadCount: diagnosis.downloadCount,
            downloadedBytes: diagnosis.downloadedBytes
        )
    }
}
