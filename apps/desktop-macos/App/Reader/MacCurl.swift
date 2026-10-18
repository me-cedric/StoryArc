import AppKit
import QuartzCore
import StoryArcCore
import SwiftUI

/// The phone's `PageCurl.metal`, as the Mac app carries it.
///
/// `ReaderFeature` is linked by path and its resource bundle, `StoryArcKit_ReaderFeature.bundle`,
/// lands in the app's resources with the compiled `default.metallib` that holds `pageCurl`. Only
/// an `xcodebuild` build compiles the shader (`AGENTS.md` section 3b), so the curl is offered
/// where the library is present and nowhere else. Task 5.1.
enum MacCurlShader {
    static let bundle: Bundle? = Bundle.main.url(forResource: "StoryArcKit_ReaderFeature", withExtension: "bundle")
        .flatMap(Bundle.init(url:))

    /// Whether this build carries the compiled shader library.
    static var isPresent: Bool { bundle?.url(forResource: "default", withExtension: "metallib") != nil }

    /// The phone's curl with the phone's constants (`PageRoll`), each sheet fitted in the view.
    static func shader(
        progress: Double, isRightToLeft: Bool, size: CGSize, turning: CGImage, under: CGImage
    ) -> Shader? {
        guard let bundle else { return nil }
        let whole = Shader.Argument.float4(0, 0, size.width, size.height)
        return ShaderLibrary.bundle(bundle).pageCurl(
            .float(progress),
            .float(Float(PageRoll.crease)),
            .float(Float(PageRoll.shadow)),
            .float(isRightToLeft ? -1 : 1),
            .float(Float(PageRoll.back)),
            .float(Float(PageRoll.radiusMax)),
            .float(Float(PageRoll.lean)),
            .float(Float(PageRoll.rim)),
            .float2(size.width, size.height),
            whole,
            whole,
            .image(Image(decorative: turning, scale: 1)),
            .image(Image(decorative: under, scale: 1))
        )
    }
}

/// A turn the curl draws over the page: the page in view, its neighbours, and how far it has turned.
///
/// `progress` runs from -1 to 1, as `CurlTurn` has it on the phone: forwards lifts `page` off
/// `beneath`, backwards lays `previous` back over `page`.
struct MacCurlTurn {
    let page: CGImage
    let beneath: CGImage?
    let previous: CGImage?
    var progress: Double = 0
}

/// A turn by key, click or wheel that the curl runs from start to end. Equal by serial alone.
struct MacCurlRequest: Equatable {
    let from: CGImage
    let to: CGImage
    let isForward: Bool
    let serial: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.serial == rhs.serial }
}

/// The curl over the page, drawn at the value SwiftUI interpolates, frame by frame.
///
/// `Animatable` hands every step of a settle to `animatableData`, which is the only place a
/// drawn value is known. SwiftUI may set it more than once a frame, so the probe counts the
/// bodies drawn instead: one a frame while the settle runs.
struct MacCurlLayer: View, @MainActor Animatable {
    var turn: MacCurlTurn
    let isRightToLeft: Bool
    let matte: Color

    var animatableData: Double {
        get { turn.progress }
        set { turn.progress = newValue }
    }

    var body: some View {
        MacCurlProbe.shared.frame()
        return GeometryReader { geometry in
            let sheets = CurlTurn.sheets(
                progress: turn.progress, page: turn.page, beneath: turn.beneath, previous: turn.previous
            )
            // The page's own rectangle turns, not the window: a Mac window is wider than its
            // page, and a sheet as wide as the window rolls its empty sides over the page.
            let sheet = Self.fitted(turn.page, in: geometry.size)
            ZStack {
                matte
                if let turning = sheets.turning, let shader = MacCurlShader.shader(
                    progress: sheets.progress, isRightToLeft: isRightToLeft, size: sheet.size,
                    turning: turning, under: sheets.under ?? turning
                ) {
                    Rectangle().fill(shader)
                        .frame(width: sheet.width, height: sheet.height)
                        .position(x: sheet.midX, y: sheet.midY)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the canvas draws a page at fit-to-screen: centred, as large as fits.
    static func fitted(_ page: CGImage, in area: CGSize) -> CGRect {
        guard page.width > 0, page.height > 0 else { return CGRect(origin: .zero, size: area) }
        let scale = min(area.width / CGFloat(page.width), area.height / CGFloat(page.height))
        let size = CGSize(width: CGFloat(page.width) * scale, height: CGFloat(page.height) * scale)
        return CGRect(origin: CGPoint(x: (area.width - size.width) / 2, y: (area.height - size.height) / 2), size: size)
    }
}

/// Frame times while a curl settles, for the record of task 5.1.
///
/// The display's own clock, a `CADisplayLink` on the screen, ticks once a refresh; a tick
/// after which the curl drew a new body is a frame presented, and the time between two such
/// ticks is the frame time. A refresh the curl missed shows as a gap of two intervals or more.
/// Off unless a settle runs; the walk reads the last settles.
@MainActor
final class MacCurlProbe: NSObject {
    static let shared = MacCurlProbe()

    /// The frame times of each finished settle, in seconds.
    private(set) var settles: [[Double]] = []
    private var stamps: [CFTimeInterval] = []
    private var drew = false
    private var link: CADisplayLink?

    func begin() {
        stamps = []
        drew = false
        link?.invalidate()
        link = (NSApplication.shared.keyWindow?.screen ?? NSScreen.main)?
            .displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    /// The curl drew a body.
    func frame() { drew = true }

    @objc private func tick(_ link: CADisplayLink) {
        guard drew else { return }
        drew = false
        stamps.append(link.timestamp)
    }

    func end() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        let times = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        if !times.isEmpty { settles = Array((settles + [times]).suffix(20)) }
    }

    func reset() { settles = [] }
}
