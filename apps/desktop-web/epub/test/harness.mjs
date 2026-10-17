// Shared by the browser tests: the static server, headless WebKit, and a page with the bundle
// loaded and one reader opened on the fixture. WebKit is the target because the macOS and
// Linux hosts are WebKit; the Windows host is WebView2 (Chromium), which the same tests can
// be pointed at with STORYARC_EPUB_BROWSER=chromium.
import { chromium, webkit } from 'playwright-core'
import { startServer } from './fixture.mjs'

const BROWSER = process.env.STORYARC_EPUB_BROWSER === 'chromium' ? chromium : webkit

export async function startHarness() {
  const server = await startServer()
  const browser = await BROWSER.launch()
  return {
    server,
    browser,
    async close() {
      await browser.close()
      await server.close()
    },
  }
}

/**
 * Opens a page on the host, the bundle loaded, a reader open. Everything the reader posts to
 * the host lands in `window.__messages`; `messages()` reads it and `waitFor` waits for one.
 */
export async function openReader(harness, { options = {} } = {}) {
  const { server, browser } = harness
  const page = await browser.newPage({ viewport: { width: 800, height: 600 } })
  const errors = []
  page.on('pageerror', (error) => errors.push(String(error)))
  await page.goto(`${server.origin}/`)
  await page.evaluate(
    async ({ manifest, positions, options }) => {
      window.__messages = []
      window.__reader = await StoryArcEpub.open({
        container: document.getElementById('reader'),
        manifest,
        positions,
        post: (message) => window.__messages.push(JSON.parse(JSON.stringify(message))),
        ...options,
      })
    },
    { manifest: server.manifest, positions: server.positions, options },
  )

  const messages = (type) =>
    page.evaluate((type) => window.__messages.filter((message) => !type || message.type === type), type)
  const waitFor = async (type, predicate = () => true, timeout = 8000) => {
    const deadline = Date.now() + timeout
    for (;;) {
      const found = (await messages(type)).filter(predicate)
      if (found.length > 0) return found[found.length - 1]
      if (Date.now() > deadline) {
        throw new Error(`no "${type}" message within ${timeout} ms; saw ${JSON.stringify(await messages())}`)
      }
      await page.waitForTimeout(50)
    }
  }
  const send = (message) => page.evaluate((message) => window.__reader.receive(message), message)
  const frame = () => page.frames().find((candidate) => candidate !== page.mainFrame() && candidate.url().startsWith('blob:'))
  return { page, errors, messages, waitFor, send, frame }
}
