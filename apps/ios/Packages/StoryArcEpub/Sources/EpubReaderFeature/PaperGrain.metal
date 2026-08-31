#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Natural's paper grain, as one stitchable Metal shader.
//
// The twin of `PaperGrain.kt`'s AGSL — same hash, same two octaves, same tints, so the
// two platforms are one texture expressed twice rather than two textures that look
// roughly alike. `design.md` chose procedural noise over a bundled tiling asset:
// cheaper, resolution-independent, and no bytes in the download.
//
// Drawn as a fill over the page rather than as a colour effect on it. The page is a web
// view, and a colour effect would have to sample content the shader is not given — an
// overlay of nearly transparent specks composites the same way and asks for nothing.
//
// Output is premultiplied, which is what SwiftUI expects from a shader used as a
// `ShapeStyle`.

/// A cheap deterministic hash of a lattice point.
///
/// The value-noise workhorse: two irrational-ish multipliers, a self-dot to decorrelate
/// the axes, and a fract to land in [0, 1). No texture, no table, no state.
static float hashed(float2 point) {
    float2 wrapped = fract(point * float2(123.34, 456.21));
    wrapped += dot(wrapped, wrapped + 45.32);
    return fract(wrapped.x * wrapped.y);
}

/// Two octaves of per-cell noise, in [-1, 1].
///
/// One octave reads as television static, because every speck is the same size. The
/// second runs at 2.17× — deliberately not 2, so the two lattices never line up — and
/// breaks the regularity into something closer to fibre.
///
/// Per-cell rather than interpolated: paper grain is not a smooth field, and skipping
/// the interpolation is both cheaper and more like the thing.
static float fibre(float2 point, float fine) {
    float coarse = hashed(floor(point));
    float finer = hashed(floor(point * 2.17) + 19.0);
    return (mix(coarse, finer, fine)) * 2.0 - 1.0;
}

[[ stitchable ]] half4 paperGrain(
    float2 position,
    // The size of one noise cell, in the shader's own coordinate space. The caller
    // divides the pixel figure by the display scale, so a cell is the same physical size
    // on every panel.
    float cell,
    // The peak alpha of a single speck.
    float intensity,
    // How much of the noise the finer octave contributes.
    float fine
) {
    float noise = fibre(position / max(cell, 0.001), fine);
    half alpha = half(abs(noise) * intensity);

    // Fibre is not neutral grey. The raised threads catch light and read warm; the
    // hollows between them are a deeper brown than they are dark. A symmetric grey
    // speckle reads as sensor noise, which is the one thing this must not look like.
    half3 tint = noise > 0.0 ? half3(1.0, 0.98, 0.94) : half3(0.35, 0.28, 0.20);

    return half4(tint * alpha, alpha);
}
