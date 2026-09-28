import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import StoryArcCore

/// The offer to copy a local reading list onto a server, in each state it can be in.
///
/// `collections-and-reading-lists`: "only servers that are reachable and hold reading lists
/// are offered", and when there are none "the offer to copy is disabled and says why, rather
/// than failing after the user has confirmed it".
///
/// The failure this guards is a quiet one. Hiding the action when no server answered would
/// also stop the copy failing, and it would leave a reader who has a server, and cannot reach
/// it, with no way to tell that from an app that cannot copy lists at all.
///
/// Android's `PromoteOfferTest` asserts these cases one for one.
@Suite("Promote offer")
struct PromoteOfferTests {

    // MARK: - Fixtures

    private func page(_ name: String) -> KavitaPage {
        KavitaPage(
            id: name,
            title: name,
            address: KavitaAddress(base: URL(filePath: "/\(name)"), apiKey: "k")
        )
    }

    private let local = ReadingList(name: "Crossover", entries: ["a", "b"])

    // MARK: - Whether the offer is there at all

    @Test("A list a server already holds is offered no copy onto a server")
    func aServerListIsNotOffered() {
        let onAServer = ReadingList(
            name: "Crossover",
            entries: ["a"],
            origin: .server(UUID())
        )

        #expect(PromoteOffer.of(onAServer, servers: [page("attic")]) == nil)
    }

    @Test("A collection screen, which has no list, is offered nothing")
    func noListIsNotOffered() {
        #expect(PromoteOffer.of(nil, servers: [page("attic")]) == nil)
    }

    // MARK: - The state the offer is in

    @Test("With no reachable server the offer stands, disabled, and carries its reason")
    func noServerDisablesAndExplains() throws {
        let offer = try #require(PromoteOffer.of(local, servers: []))

        #expect(offer.isEnabled == false)
        #expect(offer.statesWhyNot)
        #expect(offer.namedServer == nil)
    }

    @Test("One reachable server enables the offer and names it")
    func oneServerIsNamed() throws {
        let offer = try #require(PromoteOffer.of(local, servers: [page("attic")]))

        #expect(offer.isEnabled)
        #expect(offer.statesWhyNot == false)
        #expect(offer.namedServer == "attic")
    }

    @Test("Two reachable servers enable the offer and name neither")
    func twoServersAreNotNamed() throws {
        let offer = try #require(
            PromoteOffer.of(local, servers: [page("attic"), page("loft")])
        )

        #expect(offer.isEnabled)
        #expect(offer.namedServer == nil)
    }

    @Test("A reason is stated exactly when the offer cannot be acted on")
    func theReasonFollowsTheDisabling() throws {
        // The two halves of the scenario's one sentence. A disabled offer with no reason is
        // the failure it exists to prevent, moved one step earlier; a reason beside a live
        // offer would tell a reader the copy cannot happen while they are starting it.
        let away = try #require(PromoteOffer.of(local, servers: []))
        let there = try #require(PromoteOffer.of(local, servers: [page("attic")]))

        #expect(away.statesWhyNot == !away.isEnabled)
        #expect(there.statesWhyNot == !there.isEnabled)
        #expect(away.statesWhyNot != there.statesWhyNot)
    }
}
