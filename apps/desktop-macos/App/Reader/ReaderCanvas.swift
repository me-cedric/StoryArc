import AppKit
import DesignSystem
import ReaderFeature
import StoryArcCore
import SwiftUI

/// The page surface of a paged Mac reader: the spread, the turn, the fit and zoom, the drag
/// and the click zones.
///
/// SwiftUI over `ReaderModel`'s decoded pages rather than `ZoomablePage`, which is UIKit.
/// Pinch is `MagnifyGesture`; Command and the wheel, and a plain wheel turn, come through a
/// local event monitor because SwiftUI has no wheel modifier; a double click toggles the
/// zoom; a drag pans a zoomed page and slides a fitted one. A turn slides or fades by the mode
/// that runs (`PageChanges`); each page is drawn with the series' adjustments
/// (`AdjustedPage`). Tasks 2.12 to 2.15, and the wave 2 walk's transitions, fits and
/// adjustments.
struct ReaderCanvas: View {
    @Environment(\.theme) private var theme

    let state: ReaderState
    let viewport: CGSize
    let zonesOn: Bool
    let onToggleChrome: () -> Void
    let onPointerMoved: () -> Void

    @State private var baseZoom: ZoomModel?
    @State private var dragTranslation: CGFloat = 0
    @State private var wheelMonitor: WheelMonitor?

    private var model: ReaderModel { state.model }
    private var isRightToLeft: Bool { state.isRightToLeft }
    private var zoom: ZoomModel { state.zoom }

    var body: some View {
        let layout = state.layout
        let spread = layout[layout.slot(containing: model.currentIndex)] ?? Spread(leading: model.currentIndex)
        ZStack {
            spreadView(spread)
                .scaleEffect(zoom.scale)
                .offset(x: zoom.offset.width + slideOffset, y: zoom.offset.height)
                .animation(state.reduceMotion ? nil : .easeOut(duration: 0.18), value: zoom.scale)
                .id(spread.leading)
                .transition(transition)
        }
        .animation(animation, value: spread.leading)
        .frame(width: viewport.width, height: viewport.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(doubleClick.exclusively(before: singleClick))
        .simultaneousGesture(drag)
        .simultaneousGesture(magnify)
        .onContinuousHover { phase in if case .active = phase { onPointerMoved() } }
        .contextMenu { ReaderPageMenu(state: state, spread: spread) }
        .onChange(of: model.currentIndex) { refitAfterTurn() }
        .onChange(of: state.fitSerial) { state.zoom = fitted(state.model.settings.fit) }
        .onChange(of: model.displayImage(at: model.currentIndex) != nil) { _, ready in
            // The fit needs the page's size, which is known once it is decoded.
            if ready, model.settings.fit != .screen, !zoom.isZoomed { state.zoom = fitted(model.settings.fit) }
        }
        .onAppear { installWheelMonitor() }
        .onDisappear { wheelMonitor?.remove(); wheelMonitor = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("desktop.reader.pageLabel \(spread.leading + 1) \(model.pages.count)"))
    }

    /// The slide while a fitted page is dragged. The curl is wave 5.
    private var slideOffset: CGFloat { zoom.isZoomed ? 0 : dragTranslation }

    // MARK: - The turn

    private var transition: AnyTransition {
        switch state.change {
        case let .slide(fromTrailing):
            .asymmetric(
                insertion: .move(edge: fromTrailing ? .trailing : .leading),
                removal: .move(edge: fromTrailing ? .leading : .trailing)
            )
        case .fade: .opacity
        case .cut: .identity
        }
    }

    private var animation: Animation? {
        switch state.change {
        case .slide: .easeOut(duration: PageChanges.slideSeconds)
        case .fade: .easeInOut(duration: PageChanges.fadeSeconds)
        case .cut: nil
        }
    }

    // MARK: - The spread

    private func spreadView(_ spread: Spread) -> some View {
        HStack(spacing: 0) {
            ForEach(SpreadDecision.screenOrder(spread, isRightToLeft: isRightToLeft), id: \.self) { index in
                page(index, share: spread.isPair ? 0.5 : 1)
            }
        }
    }

    @ViewBuilder
    private func page(_ index: Int, share: CGFloat) -> some View {
        let slotWidth = viewport.width * share
        if let image = model.displayImage(at: index) {
            AdjustedPage(image: image, index: index, adjustments: state.adjustments(at: index))
                .frame(maxWidth: slotWidth, maxHeight: viewport.height)
        } else {
            PagePlaceholder(model: model, index: index)
                .frame(maxWidth: slotWidth, maxHeight: viewport.height)
        }
    }

    // MARK: - Fit

    /// The page's size at fit-to-screen, which the zoom is a multiple of.
    private var fittedSize: CGSize {
        guard let image = model.displayImage(at: model.currentIndex) else { return viewport }
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func fitted(_ fit: PageFit) -> ZoomModel {
        let pixels = CGFloat(model.displayImage(at: model.currentIndex)?.width ?? 0)
        return ZoomModel().fitting(
            fit, fittedSize: fittedSize, viewport: viewport, pixelWidth: pixels, isRightToLeft: isRightToLeft
        )
    }

    /// *Zoom persists across pages*: a zoom the reader made is kept, at the new page's top;
    /// a page at its fit mode's size opens the next one at that mode's size.
    private func refitAfterTurn() {
        let fit = model.settings.fit
        if fit != .screen, !zoom.isZoomed || abs(zoom.scale - fitted(fit).scale) < 0.01 {
            state.zoom = fitted(fit)
        } else {
            state.zoom = zoom.turned(isRightToLeft: isRightToLeft, fittedSize: fittedSize, viewport: viewport)
        }
    }

    // MARK: - Gestures

    private var singleClick: some Gesture {
        SpatialTapGesture().onEnded { value in
            let zone = ClickZones.zone(atX: value.location.x, width: viewport.width, zonesOn: zonesOn && !zoom.isZoomed)
            let step = ClickZones.step(for: zone, isRightToLeft: isRightToLeft)
            if step == 0 { onToggleChrome() } else { state.turn(by: step) }
        }
    }

    private var doubleClick: some Gesture {
        SpatialTapGesture(count: 2).onEnded { _ in
            state.zoom = zoom.doubleClicked().settled(fittedSize: fittedSize, viewport: viewport)
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = baseZoom ?? zoom
                baseZoom = base
                state.zoom = base.magnified(by: value.magnification).settled(fittedSize: fittedSize, viewport: viewport)
            }
            .onEnded { _ in baseZoom = nil }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if zoom.isZoomed {
                    state.zoom = zoom.panned(
                        by: CGSize(width: value.velocity.width / 60, height: value.velocity.height / 60),
                        fittedSize: fittedSize, viewport: viewport
                    )
                } else {
                    dragTranslation = value.translation.width
                }
            }
            .onEnded { value in
                defer { withAnimation(state.reduceMotion ? nil : .easeOut(duration: 0.2)) { dragTranslation = 0 } }
                guard !zoom.isZoomed else { return }
                let step = DragTurn.step(
                    translation: value.translation.width, width: viewport.width, isRightToLeft: isRightToLeft
                )
                if step != 0 { state.turn(by: step) }
            }
    }

    // MARK: - The wheel

    private func installWheelMonitor() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = WheelMonitor { event in
            if event.modifierFlags.contains(.command) {
                state.zoom = zoom.wheeled(by: event.scrollingDeltaY / 10)
                    .settled(fittedSize: fittedSize, viewport: viewport)
                return true
            }
            if zoom.isZoomed {
                let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
                state.zoom = zoom.panned(by: delta, fittedSize: fittedSize, viewport: viewport)
                return true
            }
            // *Plain wheel on a page that fits*: the wheel turns the page in a paged reader.
            if let step = WheelTurn.step(
                deltaY: event.scrollingDeltaY, deltaX: event.scrollingDeltaX,
                phase: event.phase, momentum: event.momentumPhase
            ) {
                state.turn(by: isRightToLeft && event.scrollingDeltaX != 0 ? -step : step)
                return true
            }
            return false
        }
    }
}

/// *A page that has not loaded*: a quiet placeholder, never a spinner over the artwork.
struct PagePlaceholder: View {
    @Environment(\.theme) private var theme
    let model: ReaderModel
    let index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(theme.palette.surfaceSunken)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if model.isUnavailable(at: index) {
                    Group {
                        if let codec = model.codecName(at: index) {
                            Text("desktop.reader.pageUndecodable \(codec)")
                        } else {
                            Text("desktop.reader.pageUnreadable")
                        }
                    }
                    .scaledFont(.callout).foregroundStyle(.secondary).padding()
                }
            }
    }
}

/// One wheel notch to one turn: a flick's first event turns, its momentum does not.
enum WheelTurn {
    static let threshold: CGFloat = 4

    static func step(deltaY: CGFloat, deltaX: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) -> Int? {
        guard momentum == [] || momentum == .began else { return nil }
        guard phase == [] || phase == .began || phase == .changed else { return nil }
        let delta = abs(deltaX) > abs(deltaY) ? deltaX : deltaY
        guard abs(delta) >= threshold else { return nil }
        return delta < 0 ? 1 : -1
    }
}

/// A local monitor for the wheel over this window, removed with the view.
@MainActor
final class WheelMonitor {
    private var token: Any?
    private var lastTurn = Date.distantPast

    init(handle: @escaping @MainActor (NSEvent) -> Bool) {
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window?.isKeyWindow == true else { return event }
            // One turn per flick: a trackpad sends many events for one gesture.
            if !event.modifierFlags.contains(.command), Date().timeIntervalSince(lastTurn) < 0.35 { return nil }
            let handled = MainActor.assumeIsolated { handle(event) }
            if handled { lastTurn = Date() }
            return handled ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
