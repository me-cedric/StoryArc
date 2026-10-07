#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

constexpr constant float PI = 3.14159265;

/// The page fitted, centred, inside `frame`: x, y, width and height in view points.
///
/// The frame is where the reader's own page body draws the page: the whole area at
/// fit-to-screen, or the zoomed content's rectangle at any other fit or pinch. Fitting
/// inside it is what the body's own aspect-fit image view does, so a turn starts and ends
/// on the page the reader was looking at.
static half4 fitted(texture2d<half> page, float4 frame, float2 point) {
    float2 dimensions = float2(page.get_width(), page.get_height());
    float scale = min(frame.z / dimensions.x, frame.w / dimensions.y);
    float2 size = dimensions * scale;
    float2 origin = frame.xy + (frame.zw - size) * 0.5;
    float2 uv = (point - origin) / size;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return half4(0.0);
    }
    constexpr sampler linear(coord::normalized, address::clamp_to_edge, filter::linear);
    return page.sample(linear, uv);
}

/// The sheet's own texture, in turn-space, mirrored back for a right-to-left publication.
static half4 pageAt(
    texture2d<half> page,
    float4 frame,
    float2 area,
    float direction,
    float turnX,
    float y
) {
    float actual = direction > 0.0 ? turnX : area.x - turnX;
    return fitted(page, frame, float2(actual, y));
}

/// The sheen along the top of the lip and the fold, as a Gaussian in distance.
static half sheen(float away, float2 area, float crease) {
    float reach = away / (area.x * crease);
    return half(exp(-reach * reach) * 0.5);
}

/// A page rolling, as a transliteration of `PageRoll`.
///
/// The model is explained and asserted there and in `PageRollTests`: the sheet lies flat to
/// the fold, wraps a cylinder whose lower tangent is the fold, and comes back over itself.
/// Every constant arrives as a parameter read from `PageRoll` on the Swift side, so the two
/// platforms cannot disagree about a number; `PageCurlShaderTests` guards the formula.
///
/// **A second copy of the comic reader's shader, deliberately.** A shader needs a resource
/// bundle, the design system has none, and `docs/architecture` lets no feature module depend
/// on another — the reason `PaperGrain` already states for its own. So the projection lives
/// once, in `PageRoll` in `StoryArcCore`, and the text of this file has to match
/// `ReaderFeature/PageCurl.metal` character for character. `PageCurlShaderTests` reads all
/// three shaders and is what stops the copies drifting.
[[ stitchable ]] half4 pageCurl(
    float2 position,
    float progress,
    float crease,
    float shadow,
    float direction,
    float back,
    float radiusMax,
    float lean,
    float rim,
    float2 area,
    float4 pageFrame,
    float4 beneathFrame,
    texture2d<half> page,
    texture2d<half> beneath
) {
    float x = direction > 0.0 ? position.x : area.x - position.x;
    float y = position.y;
    float radius = max(radiusMax * area.x * sin(PI * progress), 0.0);
    float bow = y / area.y;
    float fold = area.x * (1.0 - progress) + lean * radius * (0.5 - bow * bow);
    float lipRim = fold + radius;

    if (x > lipRim) {
        float beyond = (x - lipRim) / (area.x * shadow);
        half dark = half(1.0 - 0.45 * exp(-beyond * beyond));
        half4 under = fitted(beneath, beneathFrame, position);
        return half4(under.rgb * dark, under.a);
    }

    if (radius > 0.0 && x >= fold) {
        float across = clamp((x - fold) / radius, 0.0, 1.0);
        float angle = PI - asin(across);
        float lambert = -cos(angle);
        half4 curved = pageAt(page, pageFrame, area, direction, fold + radius * angle, y);
        half3 rolled = curved.rgb * half(back * (rim + (1.0 - rim) * lambert));
        return half4(saturate(rolled + sheen(x - fold, area, crease)), curved.a);
    }

    float edge = 2.0 * fold - area.x + PI * radius;

    if (x < edge) {
        return pageAt(page, pageFrame, area, direction, x, y);
    }

    half4 face = pageAt(page, pageFrame, area, direction, 2.0 * fold - x + PI * radius, y);
    half3 dimmed = face.rgb * half(back);
    return half4(saturate(dimmed + sheen(fold - x, area, crease)), face.a);
}
