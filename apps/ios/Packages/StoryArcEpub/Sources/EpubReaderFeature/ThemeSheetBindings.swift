internal import SwiftUI

internal import StoryArcCore

// The theme sheet's plumbing: the bindings its controls write through, and the one
// step helper. Split out because `ThemeSheet.swift` sat at exactly the 400-line cap,
// so the next comment anyone added pushed it over — which is what happened.
//
// A binding rather than a callback per control: each of these writes one axis and
// leaves the rest of `ThemeValues` alone, and a sheet full of `onChange` handlers is
// where an axis quietly stops being written.

extension ThemeSheet {
    var typefaceBinding: Binding<ReaderTypeface> {
        Binding(
            get: { model.values.typeface },
            set: { new in
                var values = model.values
                values.typeface = new
                model.change(.fontFamily, to: values)
            }
        )
    }

    var boldBinding: Binding<Bool> {
        Binding(
            get: { model.values.isBold },
            set: { new in
                var values = model.values
                values.isBold = new
                model.change(.boldText, to: values)
            }
        )
    }

    var alignmentBinding: Binding<ReaderTextAlignment> {
        Binding(
            get: { model.values.textAlignment },
            set: { new in
                var values = model.values
                values.textAlignment = new
                model.change(.textAlignment, to: values)
            }
        )
    }

    func step(to size: FontSizeStep) {
        var values = model.values
        values.fontSize = size
        model.change(.fontSize, to: values)
    }

    /// What Original costs, said once rather than implied by dead sliders.
}
