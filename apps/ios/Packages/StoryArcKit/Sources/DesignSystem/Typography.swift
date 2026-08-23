public import SwiftUI

/// The eleven type roles from `packages/design-tokens/tokens/typography.json`.
///
/// Sizes come from ``StoryArcType`` and are applied through `Font`'s relative
/// sizing so Dynamic Type still scales them. `native-experience` requires every
/// screen to survive the largest accessibility size.
/// The measurable part of a type role, at the default text size.
public struct TypeMetrics: Sendable, Equatable {
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let tracking: CGFloat
}

public enum TextRole: Sendable, CaseIterable {
    case display, title1, title2, title3, headline
    case body, callout, subheadline, footnote, caption, caption2

    var metrics: TypeMetrics {
        switch self {
        case .display: TypeMetrics(
            size: StoryArcType.displaySize,
            lineHeight: StoryArcType.displayLineHeight,
            tracking: StoryArcType.displayTracking
        )
        case .title1: TypeMetrics(
            size: StoryArcType.title1Size,
            lineHeight: StoryArcType.title1LineHeight,
            tracking: StoryArcType.title1Tracking
        )
        case .title2: TypeMetrics(
            size: StoryArcType.title2Size,
            lineHeight: StoryArcType.title2LineHeight,
            tracking: StoryArcType.title2Tracking
        )
        case .title3: TypeMetrics(
            size: StoryArcType.title3Size,
            lineHeight: StoryArcType.title3LineHeight,
            tracking: StoryArcType.title3Tracking
        )
        case .headline: TypeMetrics(
            size: StoryArcType.headlineSize,
            lineHeight: StoryArcType.headlineLineHeight,
            tracking: StoryArcType.headlineTracking
        )
        case .body: TypeMetrics(
            size: StoryArcType.bodySize,
            lineHeight: StoryArcType.bodyLineHeight,
            tracking: StoryArcType.bodyTracking
        )
        case .callout: TypeMetrics(
            size: StoryArcType.calloutSize,
            lineHeight: StoryArcType.calloutLineHeight,
            tracking: StoryArcType.calloutTracking
        )
        case .subheadline: TypeMetrics(
            size: StoryArcType.subheadlineSize,
            lineHeight: StoryArcType.subheadlineLineHeight,
            tracking: StoryArcType.subheadlineTracking
        )
        case .footnote: TypeMetrics(
            size: StoryArcType.footnoteSize,
            lineHeight: StoryArcType.footnoteLineHeight,
            tracking: StoryArcType.footnoteTracking
        )
        case .caption: TypeMetrics(
            size: StoryArcType.captionSize,
            lineHeight: StoryArcType.captionLineHeight,
            tracking: StoryArcType.captionTracking
        )
        case .caption2: TypeMetrics(
            size: StoryArcType.caption2Size,
            lineHeight: StoryArcType.caption2LineHeight,
            tracking: StoryArcType.caption2Tracking
        )
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title3, .headline: .semibold
        case .title1, .title2: .bold
        default: .regular
        }
    }

    /// `display` is the app's one serif moment — publication titles and series
    /// headers. Everything else is the system sans, which is what makes the
    /// chrome read as stock.
    var usesEditorialSerif: Bool { self == .display }

    /// The Dynamic Type style each role scales against.
    var textStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }
}

extension View {
    public func textRole(_ role: TextRole) -> some View {
        let metrics = role.metrics
        let font: Font = role.usesEditorialSerif
            ? .system(size: metrics.size, weight: role.weight, design: .serif)
            : .system(role.textStyle, design: .default, weight: role.weight)
        return self
            .font(font)
            .tracking(metrics.tracking)
    }
}
