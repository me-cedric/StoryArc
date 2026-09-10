#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

constexpr constant float PI = 3.14159265;

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

/// The sheet's own texture, in turn-space, mirrored back for a right-to-left publication.
static half4 pageAt(
    texture2d<half> page,
    float2 area,
    float direction,
    float turnX,
    float y
) {
    float actual = direction > 0.0 ? turnX : area.x - turnX;
    return fitted(page, area, float2(actual, y));
}

/// The sheen along the top of the lip and the fold, as a Gaussian in distance.
static half sheen(float away, float2 area, float crease) {
    float reach = away / (area.x * crease);
    return half(exp(-reach * reach) * 0.5);
}

/// A page rolling, as a transliteration of Android's `PageRoll`.
///
/// The model is explained and asserted there and in `PageRollTests`: the sheet lies flat to
/// the fold, wraps a cylinder whose lower tangent is the fold, and comes back over itself.
/// Every constant arrives as a parameter read from `PageRoll` on the Swift side, so the two
/// platforms cannot disagree about a number; `PageCurlShaderTests` guards the formula.
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
    texture2d<half> page,
    texture2d<half> beneath
) {
    float x = direction > 0.0 ? position.x : area.x - position.x;
    float y = position.y;
    float radius = max(radiusMax * area.x * sin(PI * progress), 0.0);
    float fold = area.x * (1.0 - progress) + lean * radius * (0.5 - y / area.y);
    float lipRim = fold + radius;

    if (x > lipRim) {
        float beyond = (x - lipRim) / (area.x * shadow);
        half dark = half(1.0 - 0.45 * exp(-beyond * beyond));
        half4 under = fitted(beneath, area, position);
        return half4(under.rgb * dark, under.a);
    }

    if (radius > 0.0 && x >= fold) {
        float across = clamp((x - fold) / radius, 0.0, 1.0);
        float angle = PI - asin(across);
        float lambert = -cos(angle);
        half4 curved = pageAt(page, area, direction, fold + radius * angle, y);
        half3 rolled = curved.rgb * half(back * (rim + (1.0 - rim) * lambert));
        return half4(saturate(rolled + sheen(x - fold, area, crease)), curved.a);
    }

    float edge = 2.0 * fold - area.x + PI * radius;

    if (x < edge) {
        return pageAt(page, area, direction, x, y);
    }

    half4 face = pageAt(page, area, direction, 2.0 * fold - x + PI * radius, y);
    half3 dimmed = face.rgb * half(back);
    return half4(saturate(dimmed + sheen(fold - x, area, crease)), face.a);
}
