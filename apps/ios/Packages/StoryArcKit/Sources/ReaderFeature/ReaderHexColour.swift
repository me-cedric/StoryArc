internal import SwiftUI

extension Color {
    /// `#rrggbb`, or `nil` if the string is not one.
    ///
    /// The tokens and the domain both speak hex — the tokens because Readium parses its own,
    /// the domain because a stored colour has to survive a round trip. This is the one place
    /// the reader turns one into a `Color`.
    init?(readerHex hex: String) {
        var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        // `#abc` is legal CSS and a picker may hand one over.
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
