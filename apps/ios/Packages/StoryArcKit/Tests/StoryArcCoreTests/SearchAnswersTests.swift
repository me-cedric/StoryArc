import Testing

@testable import StoryArcCore

/// The one-search merge, asserted against the same table as Android's `SearchAnswersTest`.
///
/// `library-browsing` asks for local results now and remote results later, merged without
/// disturbing what the reader is already looking at. That promise is a property of this
/// value and of nothing else, so it is asserted here — case for case on both platforms,
/// per ADR-0001. Add a case here, add it there.
@Suite("Search answers")
struct SearchAnswersTests {

    private func local(_ title: String, kind: MatchKind = .publication) -> SearchResult {
        SearchResult(kind: kind, title: title, publicationID: title)
    }

    private func remote(
        _ title: String,
        kind: MatchKind = .publication,
        from source: String = "server"
    ) -> SearchResult {
        SearchResult(kind: kind, title: title, route: SearchRoute(sourceID: source, key: title))
    }

    @Test("What the device holds is the whole answer until something else replies")
    func localIsInstant() {
        let answers = SearchAnswers(
            term: "bone",
            local: [local("Bone")],
            asking: ["server"]
        )
        #expect(answers.results.map(\.title) == ["Bone"])
        #expect(answers.isWaiting)
    }

    @Test("A late answer lands under what is already there, and moves nothing")
    func remoteAppends() {
        let before = SearchAnswers(
            term: "bone",
            local: [local("Bone"), local("Bone Sharps")],
            asking: ["server"]
        )
        let after = before.answered("server", with: [remote("Boneyard")])

        #expect(after.results.map(\.title) == ["Bone", "Bone Sharps", "Boneyard"])
        // The point of the whole type: everything the reader could already see is still
        // exactly where it was.
        #expect(after.results.prefix(2).map(\.title) == before.results.map(\.title))
        #expect(!after.isWaiting)
    }

    @Test("A server's copy of a book the device already holds is not a second row")
    func duplicatesFold() {
        let answers = SearchAnswers(term: "bone", local: [local("Bone")], asking: ["server"])
            .answered("server", with: [remote("bone"), remote("Boneyard")])

        #expect(answers.results.map(\.title) == ["Bone", "Boneyard"])
        // The one that arrived first is the one that stayed, so the row still opens the
        // copy on the device rather than sending the reader to the network for it.
        #expect(answers.results.first?.publicationID == "Bone")
    }

    @Test("A server that matched one series twice sends one row")
    func duplicatesWithinOneAnswerFold() {
        let answers = SearchAnswers(term: "bone", asking: ["server"])
            .answered("server", with: [remote("Bone", kind: .series), remote("Bone", kind: .series)])

        #expect(answers.results.count == 1)
    }

    @Test("A late answer may add a heading, and never above an existing one")
    func headingsAppend() {
        let answers = SearchAnswers(
            term: "smith",
            local: [local("Smith's Journey")],
            asking: ["server"]
        )
        .answered("server", with: [remote("Jeff Smith", kind: .person)])

        #expect(answers.groups.map(\.kind) == [.publication, .person])
    }

    @Test("Headings come in the order something first had to go under them")
    func headingOrderFollowsArrival() {
        let answers = SearchAnswers(
            term: "smith",
            local: [local("Jeff Smith", kind: .person), local("Smith's Journey")]
        )
        #expect(answers.groups.map(\.kind) == [.person, .publication])
        #expect(answers.groups.first?.results.map(\.title) == ["Jeff Smith"])
    }

    @Test("A library that cannot answer leaves the results alone and is named once")
    func failureKeepsResults() {
        let answers = SearchAnswers(term: "bone", local: [local("Bone")], asking: ["server"])
            .couldNotAnswer("server", named: "Attic shelf")

        #expect(answers.results.map(\.title) == ["Bone"])
        #expect(answers.silent.map(\.name) == ["Attic shelf"])
        #expect(!answers.isWaiting)
    }

    @Test("Failing twice does not stack a second notice")
    func failureIsNamedOnce() {
        let answers = SearchAnswers(term: "bone", asking: ["server"])
            .couldNotAnswer("server", named: "Attic shelf")
            .couldNotAnswer("server", named: "Attic shelf")

        #expect(answers.silent.count == 1)
    }

    @Test("Trying a silent library again puts it back in the queue")
    func retryRejoinsTheQueue() {
        let answers = SearchAnswers(term: "bone", asking: ["server"])
            .couldNotAnswer("server", named: "Attic shelf")
            .askingAgain("server")

        #expect(answers.silent.isEmpty)
        #expect(answers.waiting == ["server"])
        #expect(answers.isWaiting)
    }

    @Test("A retry that succeeds clears the notice and appends what it found")
    func retryThatAnswersClearsTheNotice() {
        let answers = SearchAnswers(term: "bone", local: [local("Bone")], asking: ["server"])
            .couldNotAnswer("server", named: "Attic shelf")
            .askingAgain("server")
            .answered("server", with: [remote("Boneyard")])

        #expect(answers.silent.isEmpty)
        #expect(answers.results.map(\.title) == ["Bone", "Boneyard"])
    }

    @Test("Two libraries answering in either order give the reader the same first row")
    func arrivalOrderNeverDisturbsTheTop() {
        let start = SearchAnswers(term: "bone", local: [local("Bone")], asking: ["a", "b"])
        let oneWay = start
            .answered("a", with: [remote("Boneyard", from: "a")])
            .answered("b", with: [remote("Bone Sharps", from: "b")])
        let other = start
            .answered("b", with: [remote("Bone Sharps", from: "b")])
            .answered("a", with: [remote("Boneyard", from: "a")])

        #expect(oneWay.results.first == other.results.first)
        #expect(Set(oneWay.results) == Set(other.results))
    }

    @Test("Nothing typed and nothing found is no headings at all")
    func emptyHasNoGroups() {
        #expect(SearchAnswers(term: "").groups.isEmpty)
    }

    @Test("A person a server named is a row that plainly leads nowhere")
    func namesAreNotTappable() {
        let person = SearchResult(kind: .person, title: "Jeff Smith")
        #expect(!person.isOpenable)
        #expect(SearchResult(kind: .publication, title: "Bone", publicationID: "1").isOpenable)
    }
}
