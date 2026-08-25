#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// The page curl, as one stitchable Metal shader.
//
// The twin of `PageCurl.kt`'s AGSL. `design.md` calls for one cylindrical projection
// "authored once conceptually and expressed twice rather than solved twice", and this
// is the second expression — same regions, same shading, same mirroring.
//
// It is a fold, not a cylinder. Seen straight down, a folded page shows the part not
// yet reached and the turned part lying face-down on it, and hides the crease
// entirely: the crease is edge-on and contributes no pixels from directly above. So
// the crease is shaded rather than projected. The Android spike found this and the
// reasoning is recorded in task 0.4.

/// One page, scaled to fit the area and centred, transparent outside it.
///
/// `Fit` rather than fill, for the reason the reader fits pages that way: cropping a
/// comic page loses artwork. Transparent outside, so the letterbox takes the black the
/// view paints behind rather than a smear of the page's edge pixel.
static half4 fitted(texture2d<half> page, float2 area, float2 point) {
    float2 dimensions = float2(page.get_width(), page.get_height());
    float scale = min(area.x / dimensions.x, area.y / dimensions.y);
    float2 size = dimensions * scale;
    float2 origin = (area - size) * 0.5;
    float2 uv = (point - origin) / size;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return half4(0.0);
    }
    constexpr sampler linear(coord::normalized, address::clamp_to_edge, filter::linear);
    return page.sample(linear, uv);
}

[[ stitchable ]] half4 pageCurl(
    float2 position,
    // 0 = flat, 1 = fully turned. The crease sits at (1 - progress) across.
    float progress,
    // How wide the shaded crease is, as a fraction of the page's width.
    float crease,
    // How far the cast shadow reaches beyond the crease, in the same units.
    float shadow,
    // 1 turns towards the leading edge; -1 mirrors it for right-to-left.
    float direction,
    // How much darker the back of a sheet is than its front.
    float back,
    float2 area,
    texture2d<half> page,
    texture2d<half> beneath
) {
    // One shader, two reading directions: work in a space where the turn always runs
    // towards decreasing x, and flip on the way in.
    float x = direction > 0.0 ? position.x : area.x - position.x;
    float fold = area.x * (1.0 - progress);

    // Where the turned sheet's own edge has reached. The material that used to cover
    // [fold, width] now covers [edge, fold], mirrored about the crease.
    float edge = 2.0 * fold - area.x;

    // The page, addressed in turn-space so the caller never has to mirror.
    float y = position.y;

    // Not yet reached by the sheet: the page as it lies.
    if (x < edge) {
        float actual = direction > 0.0 ? x : area.x - x;
        return fitted(page, area, float2(actual, y));
    }

    // Under the turned sheet. It is above the page, so it wins.
    if (x <= fold) {
        float mirrored = 2.0 * fold - x;
        float actual = direction > 0.0 ? mirrored : area.x - mirrored;
        half4 face = fitted(page, area, float2(actual, y));

        // The back of a page is not its front: paper is not transparent, and a
        // mirrored image at full brightness reads as a reflection rather than as a
        // turned leaf.
        half3 dimmed = face.rgb * half(back);

        // The lit crease: brightest at the fold, gone within `crease`.
        float toFold = (fold - x) / (area.x * crease);
        half lit = half(exp(-toFold * toFold) * 0.5);

        return half4(saturate(dimmed + lit), face.a);
    }

    // Lifted away from here, so the page beneath shows. Darkest against the crease,
    // which is the only place a lifted page can cast a shadow.
    float away = (x - fold) / (area.x * shadow);
    half dark = half(1.0 - 0.45 * exp(-away * away));
    half4 under = fitted(beneath, area, position);
    return half4(under.rgb * dark, under.a);
}
