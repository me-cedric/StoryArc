public import SwiftUI

extension View {
    /// Gives a control the Human Interface Guidelines' minimum hit region, 44 × 44 pt.
    ///
    /// Put it on a button's **label**. A frame or a background outside a `Button` makes the
    /// drawing bigger and leaves the area a finger hits at the size of the label, which is
    /// how a text button came to be as tall as its text. The content shape is what makes the
    /// empty part of the frame answer a tap.
    ///
    /// Related actions are one menu, never a stack of these (`design.md` §10); this is for a
    /// single action that stays a button.
    public func hitRegion(alignment: Alignment = .center) -> some View {
        frame(minWidth: 44, minHeight: 44, alignment: alignment)
            .contentShape(.rect)
    }
}
