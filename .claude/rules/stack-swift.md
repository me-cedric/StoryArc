---
description: Swift and SwiftUI rules for concurrency, modules, persistence, Keychain, touch targets, type-checker budget and tests. Applies when you edit Swift in an iOS or macOS app.
paths:
  - "**/*.swift"
  - "**/Package.swift"
  - "**/*.xcconfig"
stacks: [swift-ios, macos-desktop]
---
# Swift rules

## Language and architecture
- Use Swift 6 with strict concurrency checking. Use SwiftUI for the UI layer.
- Keep view state in `@Observable` types. Use UIKit or AppKit interop only where SwiftUI has no equivalent.
- Mark UI types `@MainActor`. Do not silence a concurrency diagnostic with `@unchecked Sendable`. Fix the isolation instead.
- Build with Swift Package Manager: one package target per feature, each with its own `README.md`.
- A target declares each module that it imports. Autolink is not a dependency: a new target that links the same module can break the incremental build of the first one.
- Keep the app target for the entry point, dependency wiring and routing only.
- Share tokens and views through a `DesignSystem` package. Put infrastructure in `Networking` and `Persistence` packages.
- Use SwiftData for local persistence. Use `URLSession` with `async` and `await` for the network. Use `Codable` for wire types.
- Store tokens in the Keychain. Do not use `UserDefaults` for a secret.
- Wire SwiftLint and swift-format into the build. Do not run them by hand.

## Type-checker budget
- Split a long chained expression (filters, maps, string interpolation, arithmetic on mixed literals) into steps with typed constants.
- Check the target with `-Xfrontend -warn-long-expression-type-checking=25`. A warning there is a CI failure on a slower Xcode.

## Touch targets (iOS)
- Grow the area that receives the tap. Keep the drawn button, capsule, chip or icon at its system size.
- Do not put a frame or content shape on the label of a `.bordered` button. The style draws its background around the label and the capsule grows.
- Write a `ButtonStyle` that wraps the system style and reserves 44 x 44 pt around it.
- Send a tap in that margin to the same action. Give the accessibility element a 44 pt frame.
- A plain row, or an icon with nothing drawn behind its label, may take the frame on the label.
- Prove it with two checks: a snapshot at system size, and a measure that shows a 44 pt touch target.

## Tests and checks
- Test units with Swift Testing. Test critical flows with XCUITest. Use Instruments when startup, hangs or memory are the subject.
- Run `xcodebuild test -scheme <scheme> -destination 'platform=iOS Simulator,name=<device>'`. On macOS, use `platform=macOS`.
- Run `swift test` when the change stays inside a package with no app target.
- Attach a screenshot from a booted simulator for a screen change: `xcrun simctl io booted screenshot screen.png`. A `#Preview` is not proof.
- Drive the running app with the `agent-device` skill. Pin one version.
- When the host installs the `swift-ios` upstream skills, read the matching skill before you write platform API code from memory.
