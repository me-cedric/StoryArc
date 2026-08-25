internal import SwiftUI

extension Color {
    /// `#rrggbb`, or `nil` if the string is not one.
    ///
    /// A second copy of the reader's reader — three lines of arithmetic, and the alternative
    /// is a shared target for a colour parser. The *contrast* logic that matters is in the
    /// domain and is not duplicated.
    init?(settingsHex hex: String) {
        var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
