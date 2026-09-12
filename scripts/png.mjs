// A PNG codec shared by the corpus generator, the Kavita mock and the capture comparison.
//
// The writers need real image bytes -- a decoder that rejects a stub proves nothing -- and a
// second copy of this would let the two disagree about what a page looks like. The reader is
// here for the same reason: `capture-compare.mjs` has to read a device screenshot back into
// pixels, and a codec written twice is a codec that disagrees with itself.
//
// Usage:
//   node scripts/png.mjs --self-test    prove the reader inverts the writer

import { pathToFileURL } from 'node:url'
import { deflateSync, inflateSync } from 'node:zlib'

/** A solid-colour PNG, shaded down the page. */
export function png(width, height, [r, g, b]) {
  const raw = Buffer.alloc((width * 3 + 1) * height)
  for (let y = 0; y < height; y += 1) {
    const row = y * (width * 3 + 1)
    raw[row] = 0 // filter: none
    for (let x = 0; x < width; x += 1) {
      // A gradient down the page, so consecutive pages are visibly different and a
      // turn that did not happen is visible in a screenshot.
      const shade = 1 - (y / height) * 0.4
      raw.writeUInt8(Math.round(r * shade), row + 1 + x * 3)
      raw.writeUInt8(Math.round(g * shade), row + 2 + x * 3)
      raw.writeUInt8(Math.round(b * shade), row + 3 + x * 3)
    }
  }
  return encode(width, height, raw)
}

/** Wraps raw truecolour scanlines as a PNG. Shared by both writers above. */
function encode(width, height, raw) {
  const chunk = (type, body) => {
    const head = Buffer.alloc(8)
    head.writeUInt32BE(body.length, 0)
    head.write(type, 4, 'ascii')
    const crc = Buffer.alloc(4)
    crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), body])) >>> 0, 0)
    return Buffer.concat([head, body, crc])
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr.writeUInt8(8, 8) // bit depth
  ihdr.writeUInt8(2, 9) // truecolour
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

/**
 * A finely ruled PNG, for proving that resolution survived a decode.
 *
 * One-pixel lines. Downsampled to a phone screen they average to flat colour; at their
 * own resolution they are stripes. That difference is the whole point: it is what makes
 * `publication-formats`' "re-decoded at higher resolution when the user zooms" something
 * a screenshot can show rather than something only a test can assert. A gradient page
 * cannot -- it looks the same at every scale, which is why the corpus needed a second
 * kind of page rather than a bigger one.
 */
export function ruledPng(width, height, [r, g, b]) {
  const raw = Buffer.alloc((width * 3 + 1) * height)
  for (let y = 0; y < height; y += 1) {
    const row = y * (width * 3 + 1)
    raw[row] = 0 // filter: none
    for (let x = 0; x < width; x += 1) {
      // Diagonal, so neither axis of a resampler can hide the pattern by luck.
      const ink = (x + y) % 2 === 0
      raw.writeUInt8(ink ? r : 255 - Math.round((255 - r) / 4), row + 1 + x * 3)
      raw.writeUInt8(ink ? g : 255 - Math.round((255 - g) / 4), row + 2 + x * 3)
      raw.writeUInt8(ink ? b : 255 - Math.round((255 - b) / 4), row + 3 + x * 3)
    }
  }
  return encode(width, height, raw)
}

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n
  for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  return c >>> 0
})

function crc32(buffer) {
  let c = 0xffffffff
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

/** Samples per pixel, by PNG colour type. Type 3 is a palette and is absent on purpose. */
const CHANNELS = { 0: 1, 2: 3, 4: 2, 6: 4 }

/**
 * A PNG back to 8-bit samples: `{ width, height, channels, pixels }`.
 *
 * Reads what the two devices produce and refuses the rest by name. Measured over the 1004
 * PNGs under `docs/designs/screenshots/` on 2026-09-12: every one is bit depth 8 and
 * non-interlaced, 410 of them colour type 2 at 1206x2622 (the iPhone 17 Pro simulator) and
 * 393 colour type 6 at 1080x2400 (the Android emulator). None is a palette and none is
 * interlaced, so neither is decoded here -- a wrong picture is worse than a refusal.
 *
 * Every read is bounds-checked against the length of the buffer, never against a length
 * field inside it, and the pixel buffer is allocated only after the decompressed size has
 * been checked. `IDAT` may be split across chunks, and libpng splits it on both platforms.
 */
export function decode(buffer) {
  if (buffer.length < 8 || !buffer.subarray(0, 8).equals(SIGNATURE)) {
    throw new Error('Not a PNG: the eight-byte signature is missing.')
  }
  let header = null
  const body = []
  let at = 8
  while (at + 8 <= buffer.length) {
    const length = buffer.readUInt32BE(at)
    const type = buffer.toString('ascii', at + 4, at + 8)
    const from = at + 8
    if (from + length + 4 > buffer.length) {
      throw new Error(`Truncated PNG: chunk ${type} runs past the end of the file.`)
    }
    if (type === 'IHDR') header = readHeader(buffer.subarray(from, from + length))
    else if (type === 'IDAT') body.push(buffer.subarray(from, from + length))
    else if (type === 'IEND') break
    at = from + length + 4
  }
  if (!header) throw new Error('Truncated PNG: the file carries no IHDR chunk.')
  if (body.length === 0) throw new Error('Truncated PNG: the file carries no IDAT chunk.')

  const { width, height, channels } = header
  const stride = width * channels
  const raw = inflateSync(Buffer.concat(body))
  const declared = (stride + 1) * height
  if (raw.length !== declared) {
    throw new Error(`Corrupt PNG: ${raw.length} decompressed bytes where the header declares ${declared}.`)
  }
  return { width, height, channels, pixels: unfilter(raw, stride, height, channels) }
}

function readHeader(ihdr) {
  if (ihdr.length !== 13) throw new Error(`Corrupt PNG: IHDR is ${ihdr.length} bytes and must be 13.`)
  const width = ihdr.readUInt32BE(0)
  const height = ihdr.readUInt32BE(4)
  const depth = ihdr.readUInt8(8)
  const colour = ihdr.readUInt8(9)
  const interlace = ihdr.readUInt8(12)
  if (width === 0 || height === 0) throw new Error(`Corrupt PNG: the header declares ${width}x${height}.`)
  if (depth !== 8) throw new Error(`Unsupported PNG: bit depth ${depth}. This reads bit depth 8.`)
  if (interlace !== 0) throw new Error('Unsupported PNG: the image is interlaced. This reads progressive images.')
  const channels = CHANNELS[colour]
  if (!channels) {
    const what = colour === 3 ? ' (a palette)' : ''
    throw new Error(`Unsupported PNG: colour type ${colour}${what}. This reads colour types 0, 2, 4 and 6.`)
  }
  return { width, height, channels }
}

/**
 * Undoes the per-scanline filter each row declares in its first byte.
 *
 * A filter predicts a sample from its neighbours and stores the difference, so decoding a
 * row needs the row above it already decoded. The row above row 0 is zeroes, by the spec.
 */
function unfilter(raw, stride, height, bpp) {
  const pixels = Buffer.alloc(stride * height)
  let prior = Buffer.alloc(stride)
  for (let y = 0; y < height; y += 1) {
    const at = y * (stride + 1)
    const type = raw[at]
    const line = raw.subarray(at + 1, at + 1 + stride)
    const row = pixels.subarray(y * stride, (y + 1) * stride)
    for (let x = 0; x < stride; x += 1) {
      const left = x >= bpp ? row[x - bpp] : 0
      const up = prior[x]
      const upLeft = x >= bpp ? prior[x - bpp] : 0
      let predicted
      if (type === 0) predicted = 0
      else if (type === 1) predicted = left
      else if (type === 2) predicted = up
      else if (type === 3) predicted = (left + up) >> 1
      else if (type === 4) predicted = paeth(left, up, upLeft)
      else throw new Error(`Corrupt PNG: filter type ${type} on row ${y}. The spec defines 0 to 4.`)
      row[x] = (line[x] + predicted) & 0xff
    }
    prior = row
  }
  return pixels
}

/** The PNG spec's predictor: whichever neighbour the linear estimate lands nearest. */
export function paeth(left, up, upLeft) {
  const estimate = left + up - upLeft
  const toLeft = Math.abs(estimate - left)
  const toUp = Math.abs(estimate - up)
  const toUpLeft = Math.abs(estimate - upLeft)
  if (toLeft <= toUp && toLeft <= toUpLeft) return left
  return toUp <= toUpLeft ? up : upLeft
}

/**
 * Wraps already-filtered scanlines as a PNG, so a test can choose the filter per row.
 *
 * `encode` is private and writes whatever it is handed; this is the same door with a name,
 * and it is what lets the self-test feed the reader rows it did not write.
 */
export function encodeFiltered(width, height, filtered) {
  return encode(width, height, filtered)
}

/**
 * Proves the reader inverts the writer, over every filter the spec defines.
 *
 * The writer emits filter 0 only, so a round trip through `png()` alone would exercise no
 * arithmetic at all. So the self-test applies each filter itself, in the forward direction,
 * and asserts the reader gives the original samples back.
 *
 * **The round trip cannot pin `paeth`, and the first version of this pretended it could.**
 * The forward direction needs the same predictor, so importing it made the fourth filter
 * compare the function against itself: replacing the whole tie-break with `return up` left
 * all 21 checks passing on 2026-09-12. The predictor is pinned by the table below instead,
 * whose rows are worked out from the spec's own rule and not from this file. With them, that
 * same mutation fails on `paeth(10, 30, 20)`. The round trip then pins everything else --
 * the neighbour indexing, the byte wrap, and the zero row above row 0 -- and a mistake in
 * either direction of it makes the two disagree. Changing the `Average` predictor from
 * `(left + up) >> 1` to `left` fails `filter 3: the samples came back changed`.
 */
function selfTest() {
  const failures = []
  const check = (ok, what) => {
    if (!ok) failures.push(what)
  }

  // left, up, upLeft, and the neighbour the spec's rule picks. Hand-worked, because a table
  // generated from the function it pins would agree with any function.
  const PAETH_VECTORS = [
    [0, 0, 0, 0],
    [1, 2, 3, 1], // estimate 0: distances 1, 2, 3 -- left
    [10, 20, 5, 20], // estimate 25: distances 15, 5, 20 -- up
    [10, 20, 30, 10], // estimate 0: distances 10, 20, 30 -- left
    [10, 30, 20, 20], // estimate 20: distances 10, 10, 0 -- upLeft, and left ties with up
    [0, 9, 3, 9], // estimate 6: distances 6, 3, 3 -- up, and up ties with upLeft
    [255, 0, 0, 255], // estimate 255: distances 0, 255, 255 -- left
  ]
  for (const [left, up, upLeft, expected] of PAETH_VECTORS) {
    const got = paeth(left, up, upLeft)
    check(got === expected, `paeth(${left}, ${up}, ${upLeft}) returned ${got}, expected ${expected}`)
  }

  // Deliberately not flat: a constant image decodes correctly under a broken predictor,
  // because every neighbour agrees. 7 is coprime with 4 and 3 so no row repeats.
  const width = 9
  const height = 10
  const channels = 3
  const stride = width * channels
  const samples = Buffer.alloc(stride * height)
  for (let i = 0; i < samples.length; i += 1) samples[i] = (i * 7 + (i % 5) * 31) & 0xff

  for (let filter = 0; filter <= 4; filter += 1) {
    const filtered = Buffer.alloc((stride + 1) * height)
    for (let y = 0; y < height; y += 1) {
      filtered[y * (stride + 1)] = filter
      for (let x = 0; x < stride; x += 1) {
        const left = x >= channels ? samples[y * stride + x - channels] : 0
        const up = y > 0 ? samples[(y - 1) * stride + x] : 0
        const upLeft = y > 0 && x >= channels ? samples[(y - 1) * stride + x - channels] : 0
        const predicted =
          filter === 0 ? 0
            : filter === 1 ? left
              : filter === 2 ? up
                : filter === 3 ? (left + up) >> 1
                  : paeth(left, up, upLeft)
        filtered[y * (stride + 1) + 1 + x] = (samples[y * stride + x] - predicted) & 0xff
      }
    }
    const read = decode(encodeFiltered(width, height, filtered))
    check(read.width === width && read.height === height, `filter ${filter}: wrong dimensions`)
    check(read.channels === channels, `filter ${filter}: ${read.channels} channels, expected ${channels}`)
    check(read.pixels.equals(samples), `filter ${filter}: the samples came back changed`)
  }

  // The writer's own output, read back. This is the path `corpus.mjs` and the Kavita mock
  // produce, so a change to either side of the file has to keep it working.
  const written = decode(png(6, 4, [200, 40, 90]))
  check(written.width === 6 && written.height === 4 && written.channels === 3, 'png(): wrong shape')
  check(written.pixels[0] === 200 && written.pixels[1] === 40 && written.pixels[2] === 90, 'png(): wrong first pixel')

  const throws = (run, what) => {
    try {
      run()
      failures.push(`${what}: no error was raised`)
    } catch {
      // The refusal is the pass.
    }
  }
  const valid = png(6, 4, [10, 20, 30])
  throws(() => decode(valid.subarray(0, valid.length - 30)), 'a truncated file')
  throws(() => decode(Buffer.alloc(64)), 'a file that is not a PNG')
  const palette = Buffer.from(valid)
  palette[25] = 3
  throws(() => decode(palette), 'a palette image')
  const interlaced = Buffer.from(valid)
  interlaced[28] = 1
  throws(() => decode(interlaced), 'an interlaced image')

  for (const failure of failures) console.error(`  ${failure}`)
  console.log(failures.length === 0 ? 'png self-test: 28 checks passed' : `png self-test FAILED: ${failures.length}`)
  process.exitCode = failures.length === 0 ? 0 : 1
}

// Only when run as a command. `corpus.mjs` and `kavita-server.mjs` import the writers, and
// an import that reads `process.argv` on the way in fails on somebody else's flags.
if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  if (process.argv.includes('--self-test')) selfTest()
  else {
    console.error('Usage: node scripts/png.mjs --self-test')
    process.exitCode = 2
  }
}
