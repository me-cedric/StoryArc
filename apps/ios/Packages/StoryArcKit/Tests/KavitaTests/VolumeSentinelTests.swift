import Testing

@testable import Kavita

/// That Kavita's two volume sentinels are recognised, and never drawn as numbers.
///
/// A series whose chapters belong to no volume was headed **-100000** on a real server, and
/// a series with specials would have been headed **100000**. Both are Kavita's own private
/// numbers for "this is not a volume".
///
/// The specials number is **positive**, which is why the guard that already caught the
/// chapter sentinel did not catch this one. Android's `VolumeSentinelTest` asserts the same
/// table.
@Suite("A volume's number, and the two sentinels that are not one")
struct VolumeSentinelTests {

    private func volume(_ number: Int) -> KavitaVolume {
        KavitaVolume(id: 1, number: number)
    }

    @Test("The current loose-leaf number is loose chapters")
    func looseLeaf() {
        #expect(volume(KavitaVolume.looseLeafVolume).isLooseChapters)
        #expect(!volume(KavitaVolume.looseLeafVolume).isSpecials)
    }

    @Test("Zero is still loose chapters, because older servers say so")
    func zero() {
        #expect(volume(0).isLooseChapters)
    }

    @Test("The specials number is specials, and it is positive")
    func specials() {
        #expect(KavitaVolume.specialVolume > 0)
        #expect(volume(KavitaVolume.specialVolume).isSpecials)
        #expect(!volume(KavitaVolume.specialVolume).isLooseChapters)
    }

    @Test("A real volume is neither")
    func realVolume() {
        for number in [1, 2, 17] {
            #expect(!volume(number).isLooseChapters)
            #expect(!volume(number).isSpecials)
        }
    }

    @Test("The numbers are the ones Kavita writes")
    func theNumbersThemselves() {
        // Quoted from `Kavita.Models/Constants/ParserConstants.cs`. A test rather than a
        // comment, because the whole defect was a number this app guessed at.
        #expect(KavitaVolume.looseLeafVolume == -100_000)
        #expect(KavitaVolume.specialVolume == 100_000)
    }
}

/// That a sentinel wearing a name is rejected too.
///
/// The first guard tested the *number*. Kavita derives a chapter's title and a volume's name
/// from the number, so the same sentinel arrives as text, and the title is read first — which
/// left the guard reachable around. Android's `NameSentinelTest` asserts the same table.
@Suite("A sentinel wearing a name")
struct NameSentinelTests {

    @Test("A sentinel is not a title")
    func sentinelTitle() {
        #expect(KavitaChapter(id: 1, number: "", title: "-100000").displayName == "")
        #expect(KavitaChapter(id: 1, number: "", title: "100000").displayName == "")
    }

    @Test("A real title survives, including one that is a number")
    func realTitle() {
        #expect(KavitaChapter(id: 1, number: "", title: "3").displayName == "3")
        #expect(KavitaChapter(id: 1, number: "", title: "Year One").displayName == "Year One")
    }

    @Test("A real number still wins when the title is a sentinel")
    func numberWins() {
        #expect(KavitaChapter(id: 1, number: "7", title: "-100000").displayName == "7")
    }

    @Test("A sentinel is not a volume name")
    func sentinelVolumeName() {
        #expect(KavitaVolume(id: 1, number: 1, name: "-100000").properName == nil)
        #expect(KavitaVolume(id: 1, number: 1, name: "100000").properName == nil)
        #expect(KavitaVolume(id: 1, number: 1, name: "Year One").properName == "Year One")
    }

    @Test("Kavita's own field decides what a volume is, before the older one")
    func minNumberWins() {
        // `VolumeExtensions.IsLooseLeaf()` reads MinNumber. A server that sends only that
        // leaves `number` at zero, and zero alone would call a specials volume loose.
        let specials = KavitaVolume(id: 1, number: 0, minNumber: 100_000)
        #expect(specials.isSpecials)
        #expect(!specials.isLooseChapters)

        #expect(KavitaVolume(id: 1, number: 0, minNumber: -100_000).isLooseChapters)

        // A fractional volume is a real volume, and neither.
        let half = KavitaVolume(id: 1, number: 1, minNumber: 1.5)
        #expect(!half.isLooseChapters)
        #expect(!half.isSpecials)
    }
}
