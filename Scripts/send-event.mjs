#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const tokenFile = process.env.DSH_DESKTOP_BRIDGE_TOKEN
  ?? join(homedir(), '.dsh', 'desktop-bridge', 'token')
const raw = process.argv[2]
if (!raw) {
  console.error('usage: node Scripts/send-event.mjs \'{"protocolVersion":1,"id":"...","type":"task.completed","title":"...","message":"..."}\'')
  process.exit(2)
}

let event
try { event = JSON.parse(raw) } catch {
  console.error('event must be valid JSON')
  process.exit(2)
}

const token = readFileSync(tokenFile, 'utf8').trim()
const response = await fetch('http://127.0.0.1:3091/v1/events', {
  method: 'POST',
  headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
  body: JSON.stringify(event),
})
const body = await response.text()
process.stdout.write(body + '\n')
if (!response.ok) process.exitCode = 1
