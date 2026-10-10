import Foundation
import Testing

import Persistence
import StoryArcCore
@testable import LibraryFeature

/// Task 25.1: the French publication page read its provenance line in English, and the
/// English line put a source name after "From" for a file the app itself holds.
///
/// `@MainActor` and `.serialized` for the reason `ChosenLanguageCatalogueTests` gives: the
/// chosen language is one value for the process.
@MainActor
@Suite("Provenance reads in the chosen language", .serialized)
struct ProvenanceFrenchTests {
    @Test("Each state reads as its whole French sentence")
    func everyStateReadsInFrench() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        let cases: [(PublicationProvenance, String)] = [
            (.init(home: .thisDevice, availability: .offline, alsoIn: nil),
             "Sur cet appareil, lisible sans réseau"),
            (.init(home: .library(name: "Attic"), availability: .now, alsoIn: nil),
             "De Attic, lisible maintenant"),
            (.init(home: .library(name: "Attic"), availability: .notHere, alsoIn: nil),
             "De Attic, pas sur cet appareil"),
            (.init(home: .library(name: "Attic"), availability: .notAnswering, alsoIn: nil),
             "De Attic, sans réponse pour le moment"),
            (.init(home: .unattributed, availability: .notHere, alsoIn: nil),
             "Dans aucune bibliothèque que vous avez ajoutée, pas sur cet appareil"),
        ]
        for (provenance, french) in cases {
            #expect(provenance.sentence == french)
        }
        let second = PublicationProvenance(home: .thisDevice, availability: .offline, alsoIn: "Attic")
        #expect(second.alsoInSentence == "Aussi dans Attic")
    }

    @Test("A file in the app's own storage reads as on this device, not as From On this device")
    func importedSourceIsNotALibraryName() {
        let imported = Source(
            id: ImportedCopies.sourceID,
            displayName: "On this device",
            kind: .localFolder,
            state: .connected
        )
        var publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/Bone 1.cbz"),
            format: .cbz,
            displayTitle: "Bone #1",
            origin: .inferred
        )
        publication.sourceID = imported.id

        let line = PublicationProvenance.of(
            publication, isOnDevice: false, hasFile: true, source: imported
        )

        #expect(line.home == .thisDevice)
        #expect(line.availability == .offline)
        #expect(line.sentence == "On this device, readable with no network")
    }

    /// Task 26.7: about 170 `String(localized:)` calls took the device language.
    @Test("A sentence built in code reads in French on an English device")
    func codeBuiltSentenceFollowsTheChosenLanguage() {
        let solid = Publication(
            identity: PublicationIdentity(contentDigest: "solid"),
            format: .cbr,
            displayTitle: "Solid",
            origin: .inferred
        )
        #expect(solid.refusalSentence == "This comic uses solid compression, which StoryArc cannot open.")
        let french = "Cette bande dessinée utilise une compression solide, que StoryArc ne peut pas ouvrir."
        InterfaceLanguage.$scoped.withValue("fr") {
            #expect(solid.refusalSentence == french)
        }
    }
}
