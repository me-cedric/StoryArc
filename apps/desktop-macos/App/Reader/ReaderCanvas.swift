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
    /// The curl standing over the page while a turn runs, or `nil`. Task 5.1.
    @State private var curl: MacCurlTurn?
    /// Which settle is in flight, so one a newer turn took over does not end that turn.
    @State private var curlTicket = 0

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
            if let curl {
                MacCurlLayer(turn: curl, isRightToLeft: isRightToLeft, matte: theme.palette.surfaceReader)
            }
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
        .onChange(of: state.curlRequest) { _, request in if let request { run(request) } }
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

    /// The slide while a fitted page is dragged in any mode but Curl.
    private var slideOffset: CGFloat { zoom.isZoomed ? 0 : dragTranslation }

    // MARK: - The curl

    /// Whether a drag on this page curls it: Curl runs and one page is in view.
    private var curls: Bool {
        guard state.choices.effective == .pageCurl, !zoom.isZoomed else { return false }
        return !(state.layout[state.layout.slot(containing: model.currentIndex)]?.isPair ?? false)
    }

    /// A turn by key, click or wheel, drawn from a flat page to a turned one.
    private func run(_ request: MacCurlRequest) {
        curl = MacCurlTurn(
            page: request.from, beneath: request.isForward ? request.to : nil,
            previous: request.isForward ? nil : request.to
        )
        // The layer appears flat first, then turns: one update would draw only the end.
        Task { @MainActor in settle(to: request.isForward ? 1 : -1) }
    }

    /// The pointer turns the page as far as it has travelled, as the phone's finger does.
    private func follow(_ translation: CGFloat) {
        let index = model.currentIndex
        guard let page = curl?.page ?? model.displayImage(at: index) else { return }
        var turn = curl ?? MacCurlTurn(
            page: page, beneath: model.displayImage(at: index + 1),
            previous: index > 0 ? model.displayImage(at: index - 1) : nil
        )
        turn.progress = CurlTurn.progress(
            base: 0, travel: translation, width: viewport.width, isRightToLeft: isRightToLeft,
            canTurnBack: turn.previous != nil, canTurnForward: turn.beneath != nil
        )
        curlTicket &+= 1
        curl = turn
    }

    /// The pointer let go: past halfway or on a flick the turn completes, else the page springs back.
    private func release(velocity: CGFloat) {
        guard let reached = curl?.progress else { return }
        let flick = CurlTurn.forward(travel: CurlTurn.predictedTravel(velocity: velocity), isRightToLeft: isRightToLeft)
        let settles = CurlTurn.settles(progress: reached, isFlick: CurlTurn.flicks(velocity: flick, progress: reached))
        // The page changes under the sheet at once; the sheet covers it until it lands.
        if settles { state.turn(by: reached < 0 ? -1 : 1, curled: true) }
        settle(to: settles ? (reached < 0 ? -1 : 1) : 0)
    }

    private func settle(to target: Double) {
        curlTicket &+= 1
        let ticket = curlTicket
        MacCurlProbe.shared.begin()
        withAnimation(state.reduceMotion ? nil : .easeInOut(duration: CurlTurn.settleDuration)) {
            curl?.progress = target
        } completion: {
            guard ticket == curlTicket else { return }
            MacCurlProbe.shared.end()
            curl = nil
        }
    }

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
                .overlay { pdfOverlay(index, imageSize: CGSize(width: image.width, height: image.height)) }
                .frame(maxWidth: slotWidth, maxHeight: viewport.height)
        } else {
            PagePlaceholder(model: model, index: index)
                .frame(maxWidth: slotWidth, maxHeight: viewport.height)
        }
    }

    /// The marks and the selection on a page of a PDF that has text, drawn in the page's fit.
    @ViewBuilder
    private func pdfOverlay(_ index: Int, imageSize: CGSize) -> some View {
        if let text = state.pdfText {
            let selection = text.selection?.locator.page == index ? (text.selection?.rects ?? []) : []
            MacPdfOverlay(imageSize: imageSize, marks: text.marks(onPage: index), selection: selection)
                .task(id: index) { await text.resolveMarks(onPage: index) }
        }
    }

    /// Where a point of the viewport falls on the shown page, in page space, for a text PDF.
    private func pagePoint(_ location: CGPoint, spread: Spread) -> (index: Int, point: CGPoint)? {
        guard !spread.isPair, let image = model.displayImage(at: spread.leading) else { return nil }
        let imageSize = CGSize(width: image.width, height: image.height)
        let point = PdfPageGeometry.normalisedPoint(location, imageSize: imageSize, in: viewport)
        return (spread.leading, point)
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
                if let text = state.pdfText, !zoom.isZoomed {
                    // A drag over a text PDF selects words, as in Preview; the wheel and the
                    // keys turn. *Text-based PDF*: the selection then offers its four things.
                    let spread = state.layout[state.layout.slot(containing: model.currentIndex)]
                        ?? Spread(leading: model.currentIndex)
                    if let from = pagePoint(value.startLocation, spread: spread),
                       let to = pagePoint(value.location, spread: spread) {
                        Task { await text.select(onPage: from.index, from: from.point, to: to.point) }
                    }
                    return
                }
                if zoom.isZoomed {
                    state.zoom = zoom.panned(
                        by: CGSize(width: value.velocity.width / 60, height: value.velocity.height / 60),
                        fittedSize: fittedSize, viewport: viewport
                    )
                } else if curls || curl != nil {
                    follow(value.translation.width)
                } else {
                    dragTranslation = value.translation.width
                }
            }
            .onEnded { value in
                defer { withAnimation(state.reduceMotion ? nil : .easeOut(duration: 0.2)) { dragTranslation = 0 } }
                guard !zoom.isZoomed else { return }
                if state.pdfText != nil { return }
                // *Scanned PDF*: a reader who drags expecting to select is told, once, in a sentence.
                if model.publication.format == .pdf { state.saysThereIsNoText = true; return }
                if curl != nil { return release(velocity: value.velocity.width) }
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
