#!/usr/bin/env node
import { createReadStream, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(process.env.DSH_WEBVIEW_SMOKE_ROOT ?? fileURLToPath(new URL('../.test-home/webview-smoke/', import.meta.url)))
const types = { '.html': 'text/html; charset=utf-8', '.txt': 'text/plain; charset=utf-8' }
const server = createServer((request, response) => {
  let path
  try { path = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname) } catch {
    response.writeHead(400).end('Bad request')
    return
  }
  const file = resolve(root, `.${path === '/' ? '/index.html' : path}`)
  if (file !== root && !file.startsWith(root + sep)) {
    response.writeHead(403).end('Forbidden')
    return
  }
  try {
    if (!statSync(file).isFile()) throw new Error('not a file')
    response.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' })
    createReadStream(file).pipe(response)
  } catch {
    response.writeHead(404).end('Not found')
  }
})

const port = Number(process.env.DSH_WEBVIEW_SMOKE_PORT ?? 13082)
server.listen(port, '127.0.0.1', () => console.log(`WKWebView smoke page: http://127.0.0.1:${port}/`))
