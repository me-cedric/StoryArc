import Foundation
import Testing

@testable import LibraryFeature

/// Task 24.1 and 24.2 of `close-the-audited-gaps`: the cover's actions are one menu, the
/// destructive row is last and alone, and removing asks first.
///
/// The owner found "Change cover", "Remove cover" and "Send this cover to the server" stacked
/// as text with each hit region as tall as its text.
struct CoverMenuTests {

    // MARK: The rows

    @Test("Every offer on: choose, find, web, send, then removal alone in its own group")
    func everyRow() {
        #expect(
            CoverMenu.rows(find: true, web: true, send: true, remove: true)
                == [[.choose, .find, .searchWeb, .sendToServer], [.remove]]
        )
    }

    @Test("The find row appears only while the lookup is on")
    func findFollowsTheOffer() {
        #expect(!CoverMenu.rows(find: false, web: true, send: false, remove: false)[0].contains(.find))
        #expect(CoverMenu.rows(find: true, web: true, send: false, remove: false)[0].contains(.find))
    }

    @Test("With nothing chosen there is nothing to remove and nothing to send on")
    func nothingToRemove() {
        let groups = CoverMenu.rows(find: true, web: true, send: false, remove: false)
        #expect(groups.count == 1)
        #expect(!groups.joined().contains(.remove))
    }

    @Test("Removal is the last row of the last group, and shares it with no other row")
    func removalIsLastAndAlone() throws {
        let groups = CoverMenu.rows(find: true, web: true, send: true, remove: true)
        #expect(groups.last == [.remove])
        #expect(groups.dropLast().allSatisfy { !$0.contains(.remove) })
    }

    // MARK: Asking first

    @Test("Removing and sending ask first, and the rest act at once")
    func whatAsksFirst() {
        let asking = Set([CoverMenuRow.choose, .find, .searchWeb, .sendToServer, .remove].filter(\.asksFirst))
        #expect(asking == [.remove, .sendToServer])
    }

    // MARK: Where the sources carry it out

    /// The cover feature's own sources, found from this file: this repository nests agent
    /// worktrees, and a walk that climbs looking for a known folder leaves the checkout.
    private func code(of name: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let path = directory.appendingPathComponent("Sources/LibraryFeature/\(name)").path
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read. A guard that cannot find what it guards passes for ever."
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("No cover file stacks borderless buttons again")
    func noStackedTextButtons() throws {
        for name in [
            "CoverChoiceView.swift", "KavitaListCover.swift", "CoverMenu.swift",
            "CoverWriteBackDialog.swift", "CoverSearchHandoff.swift",
        ] {
            let text = try code(of: name)
            for style in [".buttonStyle(.borderless)", ".buttonStyle(.link)"] {
                #expect(
                    !text.contains(style),
                    "\(name) draws a \(style). Related actions are one menu, never a stack of text buttons."
                )
            }
        }
    }

    @Test("Both screens put the one menu on the cover")
    func bothScreensPlaceTheMenu() throws {
        #expect(try code(of: "DetailHero.swift").contains(".coverEditing(menu)"))
        #expect(try code(of: "CoverChoiceView.swift").contains("cover: cover, menu: menu)"))
        #expect(try code(of: "KavitaListCover.swift").contains("well.coverEditing(menu)"))
    }

    @Test("Both screens ask before removing")
    func bothScreensAskBeforeRemoving() throws {
        #expect(try code(of: "CoverChoiceView.swift").contains(".coverRemoval(asking:"))
        #expect(try code(of: "KavitaListCover.swift").contains(".coverRemoval(asking:"))
    }
}
