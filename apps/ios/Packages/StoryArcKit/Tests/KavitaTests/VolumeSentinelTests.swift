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
