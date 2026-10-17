import AppKit
import ApplicationServices

/// The rule a control breaks.
enum AuditRule: String, Sendable {
    case unnamed = "no name"
    case tooSmall = "under 20 × 20"
}

/// An audit of a window's accessibility tree, as VoiceOver reads it.
///
/// `native-experience`, *Guidelines are checked by machine*: every control a reader can act
/// on carries a name, and is at least as large as the floor. `performAccessibilityAudit`
/// belongs to UI tests, which drive the app from a second process with an automation grant
/// an agent session does not have. The Mac tests run inside the app, so this asks the app's
/// own accessibility server through the `AXUIElement` calls VoiceOver makes. A request to
/// the process's own pid is answered in-process on the calling thread, so it is made on the
/// main thread, where AppKit expects to be asked (measured 2026-10-17: about 80 ms for the
/// library window; from a background thread AppKit logged a thread fault). Asking is also
/// what makes SwiftUI build its tree at all: before the first request a hosting view
/// reports no children.
///
/// The floor is the macOS one, 20 by 20 points for a control. Apple's *Layout* guidance
/// gives 28 as the default size on macOS and 20 as the smallest; iOS has 44. The suite
/// measures each control itself rather than trusting a framework's audit. Contrast is not
/// read here: the palette pairs are held to 4.5:1 by `pnpm tokens:check`.
@MainActor
enum AccessibilityAudit {
    nonisolated static let minimumSide: CGFloat = 20

    /// The roles a reader acts on.
    static let actionable: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXLink", "AXComboBox", "AXIncrementor", "AXDisclosureTriangle",
    ]

    /// Controls the system draws and sizes for every app: the title bar's buttons.
    static let systemSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
    ]

    /// Subtrees the system draws: a scroll bar's arrows and page areas are not the app's.
    static let systemRoles: Set<String> = ["AXScrollBar"]

    struct Control: CustomStringConvertible, Hashable, Sendable {
        let role: String
        let subrole: String
        let name: String
        let size: CGSize

        var isUnnamed: Bool { name.isEmpty }
        var isTooSmall: Bool { size.width < minimumSide || size.height < minimumSide }

        var description: String {
            "\(role)\(subrole.isEmpty ? "" : "/\(subrole)") “\(name)” \(Int(size.width))×\(Int(size.height))"
        }
    }

    /// One control that breaks a rule, on the screen it was found on.
    struct Finding: CustomStringConvertible, Hashable, Sendable {
        let screen: String
        let control: Control
        let rule: AuditRule

        var description: String { "\(screen): \(control) — \(rule.rawValue)" }
    }

    /// Every actionable control in `window` that is on screen, read as VoiceOver reads it.
    ///
    /// A control with no size is laid out nowhere (a collapsed or scrolled-away element)
    /// and is left out; the title bar's buttons and scroll bars are the system's.
    static func controls(in window: NSWindow) -> [Control] {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(app, 5)
        let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        // A sheet is no window of its own to the accessibility server: it is an `AXSheet`
        // child of the window it hangs from, which is where VoiceOver finds it too.
        let host = window.sheetParent ?? window
        guard let hostElement = windows.first(where: { frame(of: $0) == axFrame(of: host) })
            ?? windows.first(where: { string($0, kAXTitleAttribute) == host.title })
        else { return [] }
        let sheets = (value(hostElement, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            .filter { string($0, kAXRoleAttribute) == "AXSheet" }
        guard let element = window.sheetParent == nil ? hostElement : sheets.first else { return [] }
        var found: [Control] = []
        var budget = 8_000
        walk(element, depth: 0, budget: &budget, into: &found)
        return found.filter { $0.size != .zero && !systemSubroles.contains($0.subrole) }
    }

    /// The controls of `window` that break a rule, named with `screen`.
    static func findings(in window: NSWindow, screen: String) -> [Finding] {
        controls(in: window).flatMap { control -> [Finding] in
            var found: [Finding] = []
            if control.isUnnamed { found.append(Finding(screen: screen, control: control, rule: .unnamed)) }
            if control.isTooSmall { found.append(Finding(screen: screen, control: control, rule: .tooSmall)) }
            return found
        }
    }

    private static func walk(_ element: AXUIElement, depth: Int, budget: inout Int, into found: inout [Control]) {
        guard depth < 60, budget > 0 else { return }
        budget -= 1
        let role = string(element, kAXRoleAttribute) ?? ""
        if systemRoles.contains(role) { return }
        if actionable.contains(role) {
            found.append(Control(
                role: role, subrole: string(element, kAXSubroleAttribute) ?? "",
                name: name(of: element), size: frame(of: element).size
            ))
        }
        for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            walk(child, depth: depth + 1, budget: &budget, into: &found)
        }
    }

    /// What VoiceOver speaks for an element: its description, else its title, else the
    /// value of the element that titles it, else a text value or placeholder.
    private static func name(of element: AXUIElement) -> String {
        let titled = self.element(value(element, kAXTitleUIElementAttribute)).flatMap { string($0, kAXValueAttribute) }
        let candidates = [
            string(element, kAXDescriptionAttribute), string(element, kAXTitleAttribute),
            titled, string(element, kAXValueAttribute), string(element, kAXPlaceholderValueAttribute),
        ]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
    }

    /// An element's frame in the accessibility space: points, top-left origin on the main screen.
    private static func frame(of element: AXUIElement) -> CGRect {
        CGRect(origin: point(element, kAXPositionAttribute), size: size(element, kAXSizeAttribute))
    }

    /// A window's frame in the accessibility space, to find its element without trusting a title.
    private static func axFrame(of window: NSWindow) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = window.frame
        return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize {
        var size = CGSize.zero
        guard let raw = axValue(element, attribute), AXValueGetValue(raw, .cgSize, &size) else { return .zero }
        return size
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint {
        var point = CGPoint.zero
        guard let raw = axValue(element, attribute), AXValueGetValue(raw, .cgPoint, &point) else { return .zero }
        return point
    }

    /// A value that is an `AXValue`, checked by its type rather than assumed.
    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        return (raw as! AXValue) // swiftlint:disable:this force_cast
    }

    /// A value that is an element, checked by its type rather than assumed.
    private static func element(_ raw: CFTypeRef?) -> AXUIElement? {
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }
}
