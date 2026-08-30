// A PNG writer shared by the corpus generator and the Kavita mock.
//
// Both need real image bytes -- a decoder that rejects a stub proves nothing -- and a
// second copy of this would let the two disagree about what a page looks like.

import { deflateSync } from 'node:zlib'

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
