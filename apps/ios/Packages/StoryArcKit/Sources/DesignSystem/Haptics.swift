public import SwiftUI

/// The two moments StoryArc taps a reader on the wrist.
///
/// `native-experience` lists haptics among the system affordances the app has to use.
/// Which is a shorter list than it sounds: a page turn is the commonest thing that
/// happens in this app, and a comic read at speed is two hundred of them — a buzz on
/// each one is a defect, not a feature. So the vocabulary is deliberately two words
/// wide, and both of them are for something a reader would otherwise have to *notice*
/// had happened.
///
/// Nothing else gets one, on purpose:
///
/// - **A page turn** has the page itself as its feedback, and repeats forever.
/// - **The chrome appearing** is what the reader just asked for and can see.
/// - **Dragging the page slider** crosses a page a frame; a tick each would be a rattle.
/// - **A long press** already has the platform's own, from `contextMenu`.
/// - **A toggle or a slider** is answered by the control moving.
///
/// Kept word for word with Android's `StoryArcFeedback`, so a reader who owns both
/// phones is not taught two different vocabularies for one app.
public enum StoryArcFeedback: Sendable {
    /// A thing the reader finished. The end of a publication is the only one so far.
    case completion

    /// A request the app cannot honour — a page turn back from the first page.
    case refusal

    /// What the system plays for this.
    ///
    /// `SensoryFeedback`, never a `UIImpactFeedbackGenerator` of our own: SwiftUI's
    /// vocabulary is the one the device tunes for its own Taptic Engine, and it is
    /// silent when the reader has turned system haptics off.
    internal var signal: SensoryFeedback {
        switch self {
        case .completion: .success
        case .refusal: .warning
        }
    }
}

extension View {
    /// Plays `feedback` whenever `trigger` changes.
    ///
    /// A trigger rather than a call, because that is how SwiftUI models this: the
    /// feedback belongs to a change in state, and a view that plays one from inside
    /// `body` plays it again on every redraw.
    public func storyArcFeedback(
        _ feedback: StoryArcFeedback,
        trigger: some Equatable
    ) -> some View {
        sensoryFeedback(feedback.signal, trigger: trigger)
    }

    /// Plays `feedback` when `trigger` changes to a value `isWanted` accepts.
    ///
    /// For the state that goes both ways. Reaching the end of a publication earns a
    /// tap; going back to the last page from the end screen is the same flag changing
    /// again, and earns nothing.
    public func storyArcFeedback<Value: Equatable>(
        _ feedback: StoryArcFeedback,
        trigger: Value,
        when isWanted: @escaping (Value) -> Bool
    ) -> some View {
        sensoryFeedback(trigger: trigger) { _, now in isWanted(now) ? feedback.signal : nil }
    }
}
