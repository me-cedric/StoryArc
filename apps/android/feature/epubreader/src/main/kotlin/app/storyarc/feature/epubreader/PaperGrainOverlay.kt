package app.storyarc.feature.epubreader

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.semantics.clearAndSetSemantics
import app.storyarc.core.designsystem.theme.LocalIsNaturalTheme
import app.storyarc.core.designsystem.theme.PaperGrain
import app.storyarc.core.designsystem.theme.rememberHighContrast

/**
 * Natural's paper grain, as one AGSL shader.
 *
 * The twin of `PaperGrain.metal` — same hash, same two octaves, same tints, so the two
 * platforms are one texture expressed twice rather than two textures that look roughly
 * alike. `design.md` chose procedural noise over a bundled tiling asset: cheaper,
 * resolution-independent, and no bytes in the download.
 *
 * A brush rather than a `RenderEffect`, for the reason the curl is one: an effect binds
 * the view's own content to an input, and this needs no input at all. Specks composited
 * over the page ask for nothing and can be drawn above a web view the shader cannot see.
 */
private val SOURCE = """
    uniform float cell;
    uniform float intensity;
    uniform float fine;

    // A cheap deterministic hash of a lattice point.
    //
    // The value-noise workhorse: two irrational-ish multipliers, a self-dot to
    // decorrelate the axes, and a fract to land in [0, 1). No texture, no table, no
    // state.
    float hashed(float2 point) {
        float2 wrapped = fract(point * float2(123.34, 456.21));
        wrapped += dot(wrapped, wrapped + 45.32);
        return fract(wrapped.x * wrapped.y);
    }

    // Two octaves of per-cell noise, in [-1, 1].
    //
    // One octave reads as television static, because every speck is the same size. The
    // second runs at 2.17x — deliberately not 2, so the two lattices never line up — and
    // breaks the regularity into something closer to fibre.
    //
    // Per-cell rather than interpolated: paper grain is not a smooth field, and skipping
    // the interpolation is both cheaper and more like the thing.
    float fibre(float2 point) {
        float coarse = hashed(floor(point));
        float finer = hashed(floor(point * 2.17) + 19.0);
        return mix(coarse, finer, fine) * 2.0 - 1.0;
    }

    half4 main(float2 xy) {
        float noise = fibre(xy / max(cell, 0.001));
        half alpha = half(abs(noise) * intensity);

        // Fibre is not neutral grey. The raised threads catch light and read warm; the
        // hollows between them are a deeper brown than they are dark. A symmetric grey
        // speckle reads as sensor noise, which is the one thing this must not look like.
        half3 tint = noise > 0.0 ? half3(1.0, 0.98, 0.94) : half3(0.35, 0.28, 0.20);

        return half4(tint * alpha, alpha);
    }
""".trimIndent()

/**
 * Natural's paper grain, over the page and nothing else.
 *
 * `settings-and-about`: "reading surfaces gain a subtle paper grain… the texture is
 * disabled automatically when Reduce Transparency or Increase Contrast is on, because
 * grain lowers effective contrast". [PaperGrain] owns that rule, including the API 33
 * floor `RuntimeShader` imposes; this draws the result.
 *
 * Placed between the page and the chrome, which is where "reading surfaces only" puts it:
 * over the words, under the app bars. It draws and nothing else — no clickable, no
 * pointer input — so every tap still reaches the navigator underneath.
 */
@Composable
internal fun PaperGrainOverlay(modifier: Modifier = Modifier) {
    // Two reads, one rule. `PaperGrain.isDrawn` owns the product decision, the API floor
    // included; the `SDK_INT` line repeats the floor because lint cannot see through a call
    // to conclude the shader is safe to build. `CurledPages` carries the same pair for the
    // same reason.
    if (!PaperGrain.isDrawn(LocalIsNaturalTheme.current, rememberHighContrast())) return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return

    // Built once, not per frame: the uniforms never change, so a shader rebuilt on every
    // draw would be a compile per frame for a texture that is the same every time.
    val brush = remember { ShaderBrush(grainShader()) }

    Box(
        modifier
            .fillMaxSize()
            .drawBehind { drawRect(brush) }
            // A texture, not a thing to describe. TalkBack reading "image" over every page
            // would be worse than saying nothing at all.
            .clearAndSetSemantics {},
    )
}

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private fun grainShader(): RuntimeShader = RuntimeShader(SOURCE).apply {
    setFloatUniform("cell", PaperGrain.CELL_PIXELS)
    setFloatUniform("intensity", PaperGrain.INTENSITY)
    setFloatUniform("fine", PaperGrain.FINE_OCTAVE)
}
