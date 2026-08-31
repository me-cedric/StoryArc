import Foundation
import Testing

@testable import Formats

/// What a folder of files is, decided from its entries.
///
/// `publication-formats` lists a plain folder of ordered images as a publication and
/// now lists a folder of ordered audio as one too, so a folder has to be *asked* which
/// it is. The rule it gives for a folder holding both is a majority, and the
/// requirement that the app "states which it chose" is why this returns an answer
/// rather than silently picking.
@Suite("Folder kind")
struct FolderKindTests {

    @Test("A folder of images is a comic")
    func imagesAreAComic() {
        #expect(FolderKind.of(entryNames: ["page1.png", "page2.jpg", "page3.webp"]) == .comic)
    }

    @Test("A folder of audio is an audiobook")
    func audioIsAnAudiobook() {
        #expect(FolderKind.of(entryNames: ["part1.mp3", "part2.m4b", "part3.flac"]) == .audiobook)
    }

    @Test("A folder holding both is the kind most of its entries are")
    func theMajorityDecides() {
        // The corpus fixture: two audio files and one cover image.
        #expect(FolderKind.of(entryNames: ["part1.mp3", "part2.mp3", "cover.png"]) == .audiobook)
        // And the mirror, which is the far commoner case — a comic folder that
        // happens to carry a theme tune should not become an audiobook.
        #expect(FolderKind.of(entryNames: ["p1.png", "p2.png", "theme.mp3"]) == .comic)
    }

    @Test("A tie is a comic")
    func aTieIsAComic() {
        // A **product decision**, not a rule from anywhere: a folder of images is
        // what StoryArc has always made of a folder, and a tie is the one case where
        // changing that would alter existing behaviour for no stated reason.
        #expect(FolderKind.of(entryNames: ["p1.png", "part1.mp3"]) == .comic)
    }

    @Test("Entries that are neither are not counted")
    func noiseIsNotCounted() {
        // The same exclusions pages already have: resource forks, dotfiles and
        // metadata are not evidence of anything, so a folder of one page and four
        // `.DS_Store`s is still a comic rather than a folder with no majority.
        let kind = FolderKind.of(entryNames: [
            "page1.png", ".DS_Store", "._page1.png", "__MACOSX/page1.png", "ComicInfo.xml",
        ])

        #expect(kind == .comic)
    }

    @Test("A folder of nothing recognisable has no kind")
    func nothingRecognisableHasNoKind() {
        // Not a comic by default: the caller has to be able to say "this folder holds
        // no publication" rather than open an empty one.
        #expect(FolderKind.of(entryNames: ["notes.txt", "cover.psd"]) == nil)
        #expect(FolderKind.of(entryNames: []) == nil)
    }

    @Test("The corpus's own folders are what the manifest says they are")
    func corpusFoldersAgree() throws {
        // Read from disk rather than from a literal, so this fails if the fixtures
        // are regenerated differently.
        for (folder, expected) in [
            ("audiobooks/folder-parts", FolderKind.audiobook),
            ("audiobooks/mixed-folder", FolderKind.audiobook),
        ] {
            let url = FixtureCorpus.url(folder)
            let names = try FileManager.default.contentsOfDirectory(atPath: url.path)

            #expect(FolderKind.of(entryNames: names) == expected, "\(folder)")
        }
    }
}
