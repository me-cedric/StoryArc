#!/usr/bin/env node
// The listener on the far side of test/egress.html.
//
// ADR-0015's proof needs something that records whether a connection arrived, because a
// page cannot tell "the web view stopped me" from "nothing was listening". The iOS suite
// binds one loopback socket per vector; here one HTTP server on loopback does the same
// job with one path per vector, and names the vector from the path so a run says what
// escaped rather than only how many. A WebSocket upgrade is a request too, so the eighth
// vector lands on the same port.
//
// It answers nothing a browser would use. A hit is a 204, the frame gets an empty
// document, the navigation gets a redirect back to the page so the result stays visible
// (see egress.html), and the socket is closed as soon as it is counted. What matters is
// that the connection was accepted at all.
//
//   node test/collector.mjs [--port 4815]   serve egress.html and count; prints the URL
//   node test/collector.mjs --self-test     fire all eight at itself and expect 8 of 8,
//                                           and expect a stray path not to count
//
//   GET /egress.html              the page, served so it shares the collector's origin
//   GET /hit/<vector>?run=<id>    one arrival, counted under its run
//   GET /count?run=<id>           {"attempts":8,"arrived":[...],"count":n} for that run,
//                                 or every run when no id is given
//   GET /reset                    forget every run

import { createServer, get as httpGet } from 'node:http'
import { readFileSync } from 'node:fs'
import { connect } from 'node:net'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const DEFAULT_PORT = 4815
export const VECTORS = ['image', 'scriptedImage', 'fetch', 'request', 'beacon', 'socket', 'frame', 'navigation']

/** Starts a collector; resolves with its port and the functions that read and stop it. */
export function startCollector(port = 0) {
  /** @type {Map<string, Set<string>>} run id -> vectors that arrived */
  const runs = new Map()
  const record = (run, vector) => {
    if (!VECTORS.includes(vector)) return false
    if (!runs.has(run)) runs.set(run, new Set())
    runs.get(run).add(vector)
    return true
  }
  const arrived = (run) => {
    const seen = run ? [...(runs.get(run) ?? [])] : [...new Set([...runs.values()].flatMap((set) => [...set]))]
    return VECTORS.filter((vector) => seen.includes(vector))
  }

  const headers = {
    'access-control-allow-origin': '*',
    'cache-control': 'no-store',
  }

  const server = createServer((request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1')
    const run = url.searchParams.get('run') ?? ''
    const hit = url.pathname.match(/^\/hit\/([A-Za-z]+)$/)?.[1]

    if (hit) {
      if (!record(run, hit)) {
        response.writeHead(404, headers).end()
        return
      }
      if (hit === 'navigation') {
        response.writeHead(302, { ...headers, location: `/egress.html?report=${encodeURIComponent(run)}` }).end()
      } else if (hit === 'frame') {
        response.writeHead(200, { ...headers, 'content-type': 'text/html' }).end('<!doctype html><title>frame</title>')
      } else {
        response.writeHead(204, headers).end()
      }
      return
    }

    if (url.pathname === '/count') {
      const list = arrived(run || undefined)
      const body = JSON.stringify({ attempts: VECTORS.length, arrived: list, count: list.length })
      response.writeHead(200, { ...headers, 'content-type': 'application/json' }).end(body)
      return
    }

    if (url.pathname === '/reset') {
      runs.clear()
      response.writeHead(204, headers).end()
      return
    }

    if (url.pathname === '/' || url.pathname === '/egress.html') {
      const page = readFileSync(join(HERE, 'egress.html'))
      response.writeHead(200, { ...headers, 'content-type': 'text/html; charset=utf-8' }).end(page)
      return
    }

    response.writeHead(404, headers).end()
  })

  // A WebSocket is an upgrade request on the same port: count it from its path and hang
  // up. No handshake is answered, because the connection is the whole evidence.
  server.on('upgrade', (request, socket) => {
    const url = new URL(request.url, 'http://127.0.0.1')
    record(url.searchParams.get('run') ?? '', url.pathname.match(/^\/hit\/([A-Za-z]+)$/)?.[1] ?? '')
    socket.destroy()
  })

  return new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(port, '127.0.0.1', () => {
      resolve({
        port: server.address().port,
        arrived,
        stop: () => new Promise((done) => server.close(done)),
      })
    })
  })
}

/** One GET, resolved when the response ends, however it ends. */
const fetchOnce = (url) =>
  new Promise((resolve) => {
    httpGet(url, (response) => {
      response.resume()
      response.on('end', resolve)
    }).on('error', resolve)
  })

/** A raw WebSocket upgrade, resolved when the server hangs up. */
const upgradeOnce = (port, path) =>
  new Promise((resolve) => {
    const socket = connect(port, '127.0.0.1', () => {
      socket.write(
        `GET ${path} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n',
      )
    })
    socket.on('close', resolve)
    socket.on('error', resolve)
  })

const argv = process.argv.slice(2)

if (argv.includes('--self-test')) {
  // The collector is the half of the proof the page cannot supply. A collector that
  // counted nothing, or counted everything, would let both a blocked and an unblocked
  // web view report the same number.
  const collector = await startCollector(0)
  try {
    const base = `http://127.0.0.1:${collector.port}`
    const failures = []

    for (const vector of VECTORS) {
      if (vector === 'socket') await upgradeOnce(collector.port, `/hit/socket?run=a`)
      else await fetchOnce(`${base}/hit/${vector}?run=a`)
    }
    await fetchOnce(`${base}/hit/telemetry?run=a`)
    await fetchOnce(`${base}/count?run=a`)

    const a = collector.arrived('a')
    if (a.length !== VECTORS.length) failures.push(`run a: expected 8 arrivals, got ${a.length}: ${a.join(', ')}`)
    if (collector.arrived('b').length !== 0) failures.push('run b: a run that fired nothing must count nothing')
    if (a.includes('telemetry')) failures.push('a path that is not a vector was counted')

    await fetchOnce(`${base}/hit/fetch?run=b`)
    if (collector.arrived('b').join() !== 'fetch') failures.push(`run b: expected only fetch, got ${collector.arrived('b').join(', ')}`)
    if (collector.arrived().length !== VECTORS.length) failures.push('all runs together should still name every vector once')

    if (failures.length > 0) {
      for (const failure of failures) console.error(`egress collector self-test: ${failure}`)
      process.exit(1)
    }
    console.log(`egress collector self-test: ${VECTORS.length} vectors counted, a stray path was not.`)
  } finally {
    await collector.stop()
  }
  process.exit(0)
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const at = argv.indexOf('--port')
  const port = at >= 0 ? Number(argv[at + 1]) : DEFAULT_PORT
  const collector = await startCollector(port)
  console.log(`egress collector: open http://127.0.0.1:${collector.port}/egress.html`)
  console.log(`egress collector: GET http://127.0.0.1:${collector.port}/count for the arrivals; Ctrl-C to stop`)
}
