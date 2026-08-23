// oklch.mjs — OKLCH → sRGB, plus WCAG relative luminance/contrast.
//
// Tokens are authored in OKLCH because perceptual lightness is the only way to
// keep a dark and a light ramp feeling like the same family. Neither Swift nor
// Kotlin reads OKLCH, so this converts once at build time.

const clamp01 = (n) => Math.min(1, Math.max(0, n))

/** Parse `oklch(62% 0.18 48)` → { l: 0.62, c: 0.18, h: 48 }. */
export const parseOklch = (input) => {
  const match = /^oklch\(\s*([\d.]+)%\s+([\d.]+)\s+([\d.]+)\s*\)$/.exec(input.trim())
  if (!match) throw new Error(`not an oklch() value: ${input}`)
  return { l: Number(match[1]) / 100, c: Number(match[2]), h: Number(match[3]) }
}

/** OKLCH → linear-light sRGB, unclamped so out-of-gamut values stay detectable. */
const oklchToLinearRgb = ({ l, c, h }) => {
  const hRad = (h * Math.PI) / 180
  const a = c * Math.cos(hRad)
  const b = c * Math.sin(hRad)

  const lCone = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3
  const mCone = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3
  const sCone = (l - 0.0894841775 * a - 1.291485548 * b) ** 3

  return {
    r: 4.0767416621 * lCone - 3.3077115913 * mCone + 0.2309699292 * sCone,
    g: -1.2684380046 * lCone + 2.6097574011 * mCone - 0.3413193965 * sCone,
    b: -0.0041960863 * lCone - 0.7034186147 * mCone + 1.707614701 * sCone,
  }
}

const encodeGamma = (channel) =>
  channel <= 0.0031308 ? 12.92 * channel : 1.055 * channel ** (1 / 2.4) - 0.055

/** OKLCH string → `{ hex, rgb: [0-255], outOfGamut }`. */
export const oklchToSrgb = (input) => {
  const linear = oklchToLinearRgb(parseOklch(input))
  const outOfGamut = Object.values(linear).some((n) => n < -0.001 || n > 1.001)
  const rgb = [linear.r, linear.g, linear.b]
    .map((n) => Math.round(clamp01(encodeGamma(clamp01(n))) * 255))
  const hex = `#${rgb.map((n) => n.toString(16).padStart(2, '0')).join('').toUpperCase()}`
  return { hex, rgb, outOfGamut }
}

/** WCAG 2.1 relative luminance from an 0-255 sRGB triplet. */
export const relativeLuminance = ([r, g, b]) => {
  const lin = [r, g, b]
    .map((n) => n / 255)
    .map((n) => (n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4))
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
}

/** WCAG contrast ratio between two 0-255 sRGB triplets. Range 1–21. */
export const contrastRatio = (a, b) => {
  const [hi, lo] = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}
