## MODIFIED Requirements

### Requirement: Visual proof of interface changes

Every change a user can see SHALL be looked at, and checked against the platform's guidelines, before it lands, at the lowest cost that shows the screen as a user sees it.

#### Scenario: Screen change
- **WHEN** a change alters what any screen renders
- **THEN** the one who made it looks at that screen in light and dark before the change lands, from a snapshot test or from a screenshot of a booted simulator or emulator, and fixes what is wrong

#### Scenario: Snapshot tests hold the screen states
- **WHEN** a screen state can be drawn with fixture data
- **THEN** a snapshot test draws it in light and dark, on iOS on a booted simulator and on Android on the JVM, and a changed image fails the test until its reference is recorded again

#### Scenario: A device screenshot where only a device shows it
- **WHEN** a change depends on what a snapshot cannot draw: navigation between screens, system materials, window insets, system interface, or the content of a web view
- **THEN** a screenshot from a booted simulator or emulator is taken, one per appearance for each changed screen

#### Scenario: Guidelines are checked by machine
- **WHEN** the tests run
- **THEN** the suite checks every screen of the screen catalogue, and a hit target under 44 pt on iOS or 48 dp on Android, a missing label, or text under the contrast floor fails the test
- **AND** the suite measures each control itself where the platform's own check is weaker than the floor, because the platform audit can pass a target under 44 pt

#### Scenario: Preview is not proof
- **WHEN** a change is verified
- **THEN** a SwiftUI `#Preview` or a Compose `@Preview` alone does not satisfy the requirement, because neither runs in the test suite with fixture data and the platform's real drawing

#### Scenario: Both appearances
- **WHEN** a screen changes
- **THEN** it is verified in light and dark appearance at the default text size, and the largest text size is verified by the snapshot tests and the accessibility checks, not by a committed screenshot
