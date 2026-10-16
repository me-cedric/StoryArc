import Foundation
import SwiftUI
import Testing

@testable import StoryArc

/// The chrome accent of task 2.23e: brand when nothing is stored, the system accent once
/// chosen, a later system change reaching the chrome, and a cover's colour unchanged.
@MainActor
@Suite("Chrome accent")
struct ChromeAccentTests {
    private func settings() throws -> (MacSettings, ScratchDefaults) {
        let scratch = try ScratchDefaults(prefix: "mac-accent-")
        let defaults = scratch.defaults
        return (MacSettings(defaults: defaults), scratch)
    }

    @Test("The brand colour when nothing is stored, whatever the system accent")
    func brandByDefault() throws {
        let (settings, scratch) = try settings()
        defer { scratch.remove() }
        let defaults = scratch.defaults
        let accent = AccentModel(systemAccent: .green)

        #expect(settings.accent == .brand)
        #expect(accent.chromeColour(for: settings.accent, brand: .orange) == .orange)
    }

    @Test("The system accent once the reader chooses it, with no restart, and it is remembered")
    func systemOnceChosen() throws {
        let (settings, scratch) = try settings()
        defer { scratch.remove() }
        let defaults = scratch.defaults
        let accent = AccentModel(systemAccent: .green)

        settings.accent = .system

        #expect(accent.chromeColour(for: settings.accent, brand: .orange) == .green)
        #expect(MacSettings(defaults: defaults).accent == .system)
    }

    @Test("A later change of the system accent recolours the chrome while the app is open")
    func systemAccentChanges() {
        let accent = AccentModel(systemAccent: .green)

        accent.systemAccentChanged(to: .purple)

        #expect(accent.chromeColour(for: .system, brand: .orange) == .purple)
        #expect(accent.chromeColour(for: .brand, brand: .orange) == .orange)
    }

    @Test("A colour taken from a cover is the same under both choices")
    func coverColourIsUntouched() {
        #expect(AccentModel.coverAccent(.red, choice: .brand) == .red)
        #expect(AccentModel.coverAccent(.red, choice: .system) == .red)
        #expect(AccentModel.coverAccent(nil, choice: .system) == nil)
    }

    @Test("Text size and cover-alone are stored beside the shared settings")
    func macOnlyChoicesPersist() throws {
        let (settings, scratch) = try settings()
        defer { scratch.remove() }
        let defaults = scratch.defaults
        #expect(settings.textSize == .default)
        #expect(settings.coverAlone)

        settings.textSize = .largest
        settings.coverAlone = false
        settings.settings.turnPagesByTappingTheEdges = false

        let again = MacSettings(defaults: defaults)
        #expect(again.textSize == .largest)
        #expect(!again.coverAlone)
        #expect(!again.settings.turnPagesByTappingTheEdges)
        #expect(ChromeTextSize.largest.dynamicTypeSize > ChromeTextSize.default.dynamicTypeSize)
    }
}
