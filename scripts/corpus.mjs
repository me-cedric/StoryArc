#!/usr/bin/env node
// Builds a small library of real publications, one per format the app claims to read.
//
// It exists because device verification kept depending on files that happened to be on
// one simulator. A folder that only one machine has is not a fixture, and when that
// container was wiped the corpus went with it. This regenerates the same library from
// nothing, so a screenshot taken on a fresh device means what a screenshot taken on
// mine means.
//
// Usage: node scripts/corpus.mjs <directory>
//        node scripts/corpus.mjs --simulator     (writes into the booted app's Documents)

import { execFileSync } from 'node:child_process'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'

import { png, ruledPng } from './png.mjs'

const PALETTE = [
  [214, 90, 44], [58, 96, 158], [72, 138, 96],
  [148, 78, 148], [176, 148, 52], [96, 108, 128],
]

/** Pages for one issue, at comic proportions. */
function pages(count, colour) {
  return Array.from({ length: count }, (_, i) => ({
    name: `page-${String(i + 1).padStart(3, '0')}.png`,
    body: png(120, 180, PALETTE[(colour + i) % PALETTE.length]),
  }))
}

/** Writes files into a scratch directory and archives it with the platform's own tool. */
function archive(files, run) {
  const scratch = mkdtempSync(join(tmpdir(), 'storyarc-corpus-'))
  try {
    for (const file of files) {
      const path = join(scratch, file.name)
      mkdirSync(join(path, '..'), { recursive: true })
      writeFileSync(path, file.body)
    }
    run(scratch, files.map((file) => file.name))
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
}

const zip = (out, files, extra = []) =>
  archive(files, (scratch, names) =>
    execFileSync('zip', ['-q', '-X', ...extra, out, ...names], { cwd: scratch }))

const tar = (out, files) =>
  archive(files, (scratch, names) =>
    execFileSync('tar', ['-cf', out, ...names], { cwd: scratch }))

/** A reflowable book, or a fixed-layout one when `fixed` is set. */
function epub(out, { title, series, index, chapters, fixed }) {
  const spine = Array.from({ length: chapters }, (_, i) => `c${i + 1}`)
  const layout = fixed
    ? '<meta property="rendition:layout">pre-paginated</meta>'
    : ''
  const files = [
    // The mimetype has to be the first entry and stored uncompressed. `zip -X` with the
    // file listed first is how the spec's own examples are built.
    { name: 'mimetype', body: Buffer.from('application/epub+zip') },
    {
      name: 'META-INF/container.xml',
      body: Buffer.from(`<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>`),
    },
    {
      name: 'OEBPS/content.opf',
      body: Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"
  prefix="rendition: http://www.idpf.org/vocab/rendition/#">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:storyarc:${index}</dc:identifier>
    <dc:title>${title}</dc:title>
    <dc:creator>Ada Lovelace</dc:creator>
    <dc:language>en</dc:language>
    ${series ? `<meta property="belongs-to-collection" id="s">${series}</meta>
    <meta refines="#s" property="collection-type">series</meta>
    <meta refines="#s" property="group-position">${index}</meta>` : ''}
    ${layout}
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    ${spine.map((id) => `<item id="${id}" href="${id}.xhtml"
      media-type="application/xhtml+xml"/>`).join('\n    ')}
    ${fixed ? spine.map((id) => `<item id="${id}-img" href="${id}.png"
      media-type="image/png"/>`).join('\n    ') : ''}
  </manifest>
  <spine>${spine.map((id) => `<itemref idref="${id}"/>`).join('')}</spine>
</package>`),
    },
    {
      name: 'OEBPS/nav.xhtml',
      body: Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head><body><nav epub:type="toc"><ol>
${spine.map((id, i) => `<li><a href="${id}.xhtml">Chapter ${i + 1}</a></li>`).join('\n')}
</ol></nav></body></html>`),
    },
    // A fixed-layout book is a **picture per page**, and that is the whole difference.
    // This generator used to write the same wall of sentences either way and only add
    // `rendition:layout` to the metadata, which made `Bright Panels.epub` a pre-paginated
    // *text* book -- legal EPUB, and nothing like what the app routes a fixed-layout
    // publication to an image reader in order to show. The consequence was found on a
    // simulator: opening it landed on "This comic has no pages StoryArc can show", because
    // there were genuinely no images in it, so the fixed-layout path had never once been
    // exercised against something it could draw.
    ...spine.map((id, i) => ({
      name: `OEBPS/${id}.xhtml`,
      body: Buffer.from(fixed
        ? `<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Page ${i + 1}</title>
<meta name="viewport" content="width=600, height=900"/></head>
<body style="margin:0"><img src="${id}.png" alt="Page ${i + 1}" width="600" height="900"/></body>
</html>`
        : `<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter ${i + 1}</title></head>
<body><h1>Chapter ${i + 1}</h1>
${Array.from({ length: 14 }, (_, p) => `<p>${'Sentence '.repeat(24)}${i + 1}.${p + 1}</p>`).join('\n')}
</body></html>`),
    })),
    // The plates themselves, at the viewport the pages declare.
    ...(fixed
      ? spine.map((id, i) => ({
          name: `OEBPS/${id}.png`,
          body: png(600, 900, PALETTE[i % PALETTE.length]),
        }))
      : []),
  ]
  archive(files, (scratch, names) => {
    execFileSync('zip', ['-q', '-X', '-0', out, 'mimetype'], { cwd: scratch })
    execFileSync('zip', ['-q', '-X', '-r', out, ...names.filter((n) => n !== 'mimetype')],
      { cwd: scratch })
  })
}

/**
 * A publication that declares no cover and opens on one anyway.
 *
 * `publication-formats` says the first page of the spine becomes the cover when nothing
 * is declared, and this is the shape that is actually true of: an XHTML wrapper around a
 * single image, which is what a fixed-layout page is by construction. Without a file like
 * this the rule can only be asserted in a test — the library grid has nothing to draw.
 */
function spineCoverEpub(out, { title, plates }) {
  const spine = Array.from({ length: plates }, (_, i) => `p${i + 1}`)
  const files = [
    { name: 'mimetype', body: Buffer.from('application/epub+zip') },
    {
      name: 'META-INF/container.xml',
      body: Buffer.from(`<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>`),
    },
    {
      name: 'OEBPS/content.opf',
      // No `cover-image` property anywhere, and none of EPUB 2's `<meta name="cover">`
      // either. The cover has to be found rather than read off.
      body: Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"
  prefix="rendition: http://www.idpf.org/vocab/rendition/#">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:storyarc:spine-cover</dc:identifier>
    <dc:title>${title}</dc:title>
    <dc:creator>Ada Lovelace</dc:creator>
    <dc:language>en</dc:language>
    <meta property="rendition:layout">pre-paginated</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    ${spine.map((id) => `<item id="${id}" href="${id}.xhtml"
      media-type="application/xhtml+xml"/>`).join('\n    ')}
    ${spine.map((id) => `<item id="img-${id}" href="${id}.png"
      media-type="image/png"/>`).join('\n    ')}
  </manifest>
  <spine>${spine.map((id) => `<itemref idref="${id}"/>`).join('')}</spine>
</package>`),
    },
    {
      name: 'OEBPS/nav.xhtml',
      body: Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head><body><nav epub:type="toc"><ol>
${spine.map((id, i) => `<li><a href="${id}.xhtml">Plate ${i + 1}</a></li>`).join('\n')}
</ol></nav></body></html>`),
    },
    ...spine.map((id, i) => ({
      name: `OEBPS/${id}.xhtml`,
      body: Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Plate ${i + 1}</title>
<meta name="viewport" content="width=240, height=360"/></head>
<body><img src="${id}.png" width="240" height="360"/></body></html>`),
    })),
    ...spine.map((id, i) => ({
      name: `OEBPS/${id}.png`,
      body: png(240, 360, PALETTE[i % PALETTE.length]),
    })),
  ]
  archive(files, (scratch, names) => {
    execFileSync('zip', ['-q', '-X', '-0', out, 'mimetype'], { cwd: scratch })
    execFileSync('zip', ['-q', '-X', '-r', out, ...names.filter((n) => n !== 'mimetype')],
      { cwd: scratch })
  })
}

/** A PDF with real pages, written by hand — no dependency renders text this simply. */
function pdf(out, { title, pages: count }) {
  const objects = []
  const kids = Array.from({ length: count }, (_, i) => `${4 + i * 2} 0 R`).join(' ')
  objects.push(`<< /Type /Catalog /Pages 2 0 R >>`)
  objects.push(`<< /Type /Pages /Count ${count} /Kids [${kids}] >>`)
  objects.push(`<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>`)
  for (let i = 0; i < count; i += 1) {
    // Inside the MediaBox. Text placed above it renders a blank page, which looks
    // exactly like a decoder that failed and sent the first version of this corpus
    // chasing a bug in the reader that was never there.
    const stream = `BT /F1 24 Tf 48 500 Td (${title}) Tj ET\n` +
      `BT /F1 64 Tf 48 380 Td (${i + 1}) Tj ET\n` +
      `BT /F1 14 Tf 48 320 Td (page ${i + 1} of ${count}) Tj ET`
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 595] ` +
      `/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>`)
    objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`)
  }
  let body = '%PDF-1.4\n'
  const offsets = []
  objects.forEach((object, i) => {
    offsets.push(body.length)
    body += `${i + 1} 0 obj\n${object}\nendobj\n`
  })
  const startxref = body.length
  body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
  for (const offset of offsets) body += `${String(offset).padStart(10, '0')} 00000 n \n`
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n` +
    `startxref\n${startxref}\n%%EOF\n`
  writeFileSync(out, body, 'latin1')
}

function build(root) {
  rmSync(root, { recursive: true, force: true })
  mkdirSync(root, { recursive: true })
  const at = (name) => join(root, name)

  // A series, so the reader's "next in series" has something to offer.
  for (let issue = 1; issue <= 3; issue += 1) {
    zip(at(`Tidal Reach ${String(issue).padStart(2, '0')}.cbz`), pages(8, issue))
  }
  zip(at('Quiet Machines.cbz'), pages(12, 4))

  // Every other container the app says it reads.
  tar(at('Paper Lanterns.cbt'), pages(6, 2))

  // A folder of images is a publication too, and the only one with no container to open.
  const folder = at('Salt and Iron')
  mkdirSync(folder, { recursive: true })
  for (const page of pages(5, 5)) writeFileSync(join(folder, page.name), page.body)

  epub(at('The Long Field.epub'), { title: 'The Long Field', index: 1, chapters: 6 })
  epub(at('Harbour Lights 01.epub'),
    { title: 'Harbour Lights 01', series: 'Harbour Lights', index: 1, chapters: 4 })
  epub(at('Harbour Lights 02.epub'),
    { title: 'Harbour Lights 02', series: 'Harbour Lights', index: 2, chapters: 4 })
  epub(at('Bright Panels.epub'),
    { title: 'Bright Panels', index: 1, chapters: 3, fixed: true })

  pdf(at('Field Notes.pdf'), { title: 'Field Notes', pages: 5 })

  // A book that names no cover. Before the spine fallback existed, every EPUB above
  // drew a placeholder in the grid and there was no file that could show otherwise.
  spineCoverEpub(at('Glasshouse.epub'), { title: 'Glasshouse', plates: 4 })

  // Pages worth zooming into. At 2400x3600 the reader decodes them to a fraction of
  // their size, and the ruling averages to flat colour until a held zoom re-decodes
  // them — which is the only way `publication-formats`' re-decode is visible in a
  // screenshot rather than only in an assertion.
  zip(at('Fine Print.cbz'), Array.from({ length: 3 }, (_, i) => ({
    name: `page-${String(i + 1).padStart(3, '0')}.png`,
    body: ruledPng(2400, 3600, PALETTE[i % PALETTE.length]),
  })))

  // A comic converted in bulk to a codec this device has no decoder for. Every page
  // is refused, which is the case `publication-formats` means by "a page in an
  // unsupported codec displays a placeholder naming the codec" -- and the case a
  // reader has to be able to tell from the half-copied file below, which is why both
  // are here and why the placeholder says which codec it was.
  zip(at('Foreign Codec.cbz'), Array.from({ length: 3 }, (_, i) => ({
    name: `page-${String(i + 1).padStart(3, '0')}.jxl`,
    body: Buffer.concat([Buffer.from([0xff, 0x0a]), Buffer.alloc(30 + i)]),
  })), ['-0'])

  // A comic that arrived half-copied: one page the decoder will not have, and one
  // entry with nothing in it. `publication-formats` asks for both to be *said* — the
  // codec named in the placeholder, and the skipped entry counted — and neither
  // sentence is reachable without a file like this.
  // Stored rather than deflated, so the JXL signature is in the archive's own bytes
  // and the self-test below can see it. PNG is already compressed; storing costs nothing.
  zip(at('Broken Transfer.cbz'), [
    ...pages(2, 3),
    // A real JPEG XL codestream signature and nothing behind it. Neither platform
    // ships a decoder, so what is behind the signature is never reached; what matters
    // is that the placeholder names it.
    { name: 'page-003.jxl', body: Buffer.concat([Buffer.from([0xff, 0x0a]), Buffer.alloc(30)]) },
    { name: 'page-004.png', body: Buffer.alloc(0) },
  ], ['-0'])

  // Deliberately unreadable, so the refusal path has something to refuse. `local-library`
  // requires the app to name the format it found rather than fail generically, and that
  // sentence is only ever exercised by a file like this one.
  writeFileSync(at('Sealed Archive.cb7'), Buffer.from('7z\xBC\xAF\x27\x1C', 'latin1'))

  return root
}

const target = process.argv[2]
if (!target) {
  console.error('usage: node scripts/corpus.mjs <directory> | --simulator | --self-test')
  process.exit(2)
}

if (target === '--self-test') {
  // The generator writes three container formats and two file formats by hand. A
  // publication that is subtly malformed looks exactly like a reader that cannot open it,
  // and the first version of this file sent me hunting a PDF bug that was mine. So the
  // check is on the bytes: each file starts with what its format says it starts with.
  const scratch = mkdtempSync(join(tmpdir(), 'storyarc-corpus-test-'))
  try {
    build(scratch)
    const { readFileSync, readdirSync, statSync } = await import('node:fs')
    const head = (name, length) => readFileSync(join(scratch, name)).subarray(0, length)
    const checks = [
      ['Tidal Reach 01.cbz', () => head('Tidal Reach 01.cbz', 2).toString() === 'PK'],
      ['Paper Lanterns.cbt', () => statSync(join(scratch, 'Paper Lanterns.cbt')).size % 512 === 0],
      ['The Long Field.epub', () => {
        const bytes = readFileSync(join(scratch, 'The Long Field.epub'))
        // The mimetype must be the first entry and stored, per OCF.
        return bytes.subarray(30, 38).toString() === 'mimetype' &&
          bytes.readUInt16LE(8) === 0 &&
          bytes.includes(Buffer.from('application/epub+zip'))
      }],
      ['Field Notes.pdf', () => {
        const text = readFileSync(join(scratch, 'Field Notes.pdf'), 'latin1')
        // Every /Length must match the stream it describes, or a viewer reads garbage.
        for (const [, declared, stream] of
          text.matchAll(/<< \/Length (\d+) >>\nstream\n([\s\S]*?)\nendstream/g)) {
          if (Number(declared) !== stream.length) return false
        }
        return text.startsWith('%PDF-') && text.trimEnd().endsWith('%%EOF')
      }],
      ['Salt and Iron', () => readdirSync(join(scratch, 'Salt and Iron')).length === 5],
      ['page pixels', () => head(join('Salt and Iron', 'page-001.png'), 8)
        .equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))],
      ['Glasshouse.epub', () => {
        const bytes = readFileSync(join(scratch, 'Glasshouse.epub'))
        // No declared cover: the point of the file is that one has to be found.
        return !bytes.includes(Buffer.from('cover-image')) &&
          bytes.includes(Buffer.from('p1.png'))
      }],
      ['Broken Transfer.cbz', () => {
        const bytes = readFileSync(join(scratch, 'Broken Transfer.cbz'))
        // The JXL signature has to survive the zip, or the placeholder names nothing.
        return bytes.includes(Buffer.from('page-003.jxl')) &&
          bytes.includes(Buffer.from([0xff, 0x0a]))
      }],
    ]
    const failed = checks.filter(([, holds]) => !holds()).map(([name]) => name)
    if (failed.length) {
      console.error(`corpus self-test failed: ${failed.join(', ')}`)
      process.exit(1)
    }
    console.log(`corpus self-test: ${checks.length} checks passed`)
    process.exit(0)
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
}

let root = target
if (target === '--simulator') {
  const container = execFileSync('xcrun',
    ['simctl', 'get_app_container', 'booted', 'app.storyarc.StoryArc', 'data'],
    { encoding: 'utf8' }).trim()
  if (!existsSync(container)) throw new Error(`no booted app container: ${container}`)
  root = join(container, 'Documents', 'Corpus')
}

build(resolve(root))
console.log(`corpus: ${resolve(root)}`)
