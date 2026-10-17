// A reader for the one thing the tests need from an EPUB: the entries, their bytes and their
// compressed sizes. The compressed size is what the position count is made from (design.md,
// Decision 6: ceil(compressed / 1024), minimum 1), so a general unzip would hide the number.
import { readFileSync } from 'node:fs'
import { inflateRawSync } from 'node:zlib'

const EOCD = 0x06054b50
const CENTRAL = 0x02014b50

/** @returns {Map<string, {compressedSize: number, bytes: () => Buffer}>} */
export function readZip(path) {
  const zip = readFileSync(path)
  let end = zip.length - 22
  while (end >= 0 && zip.readUInt32LE(end) !== EOCD) end -= 1
  if (end < 0) throw new Error(`${path} is not a zip file`)

  const count = zip.readUInt16LE(end + 10)
  let at = zip.readUInt32LE(end + 16)
  const entries = new Map()
  for (let i = 0; i < count; i += 1) {
    if (zip.readUInt32LE(at) !== CENTRAL) throw new Error(`${path}: bad central directory`)
    const method = zip.readUInt16LE(at + 10)
    const compressedSize = zip.readUInt32LE(at + 20)
    const nameLength = zip.readUInt16LE(at + 28)
    const extraLength = zip.readUInt16LE(at + 30)
    const commentLength = zip.readUInt16LE(at + 32)
    const local = zip.readUInt32LE(at + 42)
    const name = zip.toString('utf8', at + 46, at + 46 + nameLength)
    const data = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28)
    entries.set(name, {
      compressedSize,
      bytes: () => {
        const raw = zip.subarray(data, data + compressedSize)
        return method === 0 ? raw : inflateRawSync(raw)
      },
    })
    at += 46 + nameLength + extraLength + commentLength
  }
  return entries
}
