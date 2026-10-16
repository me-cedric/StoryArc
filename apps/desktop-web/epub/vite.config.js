// One JavaScript file, nothing else. The three desktop hosts embed dist/storyarc-epub.js
// and serve it on their own scheme (ADR-0018 D6), so the build may not split chunks, emit
// a stylesheet, or write a source map beside it: a second file is a second thing to pin.
//
// The banner carries the toolkit's BSD-3-Clause notice, read from the installed package
// rather than copied here, because the licence requires the notice to travel with the
// binary and the bundle is the binary. The minifier keeps `/*!` comments.
import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'

const licence = readFileSync(new URL('./node_modules/@readium/navigator/LICENSE', import.meta.url), 'utf8')
  .trimEnd()
  .split('\n')
  .map((line) => ` * ${line}`.trimEnd())
  .join('\n')

const banner = [
  '/*!',
  ' * StoryArc EPUB bundle: @readium/navigator and @readium/shared from readium/ts-toolkit.',
  ' * https://github.com/readium/ts-toolkit',
  ' *',
  licence,
  ' */',
].join('\n')

export default defineConfig({
  build: {
    lib: {
      entry: 'src/index.js',
      name: 'StoryArcEpub',
      formats: ['iife'],
      fileName: () => 'storyarc-epub.js',
    },
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: false,
    rolldownOptions: {
      // Vite sets `comments.legal` to false whenever it minifies, which strips the
      // banner after it is added. Legal comments are `/*!`, `@license` and `@preserve`.
      output: { banner, comments: { legal: true } },
    },
  },
})
