import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const root = mkdtempSync(join(tmpdir(), 'dsh-desktop-harness-bridge-'))
process.env.DSH_HOME = root
const token = 'a'.repeat(64)
mkdirSync(join(root, 'desktop-bridge'), { recursive: true })
writeFileSync(join(root, 'desktop-bridge', 'token'), token + '\n')

let desktopAvailable = true
const desktopEvents = []
globalThis.fetch = async (_url, options) => {
  if (!desktopAvailable) throw new Error('desktop unavailable')
  desktopEvents.push(JSON.parse(options.body))
  return { ok: true }
}

const routes = new Map()
const hooks = new Map()
const disposers = []
let followup = null
const agent = {
  id: 'session-verify', status: 'idle',
  session: { id: 'session-verify', events: [] },
  followup(message) { followup = message },
}
const ctx = {
  agents: { list: () => [agent] },
  webServer: { register: ({ path, handler }) => { routes.set(path, handler); return () => routes.delete(path) } },
  effect(factory) { const dispose = factory(); if (typeof dispose === 'function') disposers.push(dispose) },
  on(name, callback, options) {
    const list = hooks.get(name) ?? []
    if (options === true || options?.prepend) list.unshift(callback); else list.push(callback)
    hooks.set(name, list)
    return () => { const at = list.indexOf(callback); if (at >= 0) list.splice(at, 1) }
  },
}

function invoke(path, body = null) {
  return new Promise((resolve, reject) => {
    const request = new EventEmitter()
    request.method = body === null ? 'GET' : 'POST'
    request.headers = { authorization: `Bearer ${token}` }
    const response = {
      status: 0, headers: {}, body: '',
      writeHead(status, headers) { this.status = status; this.headers = headers },
      end(value = '') { this.body = value; resolve(this) },
    }
    Promise.resolve(routes.get(path)(request, response)).catch(reject)
    queueMicrotask(() => {
      if (body !== null) request.emit('data', Buffer.from(JSON.stringify(body)))
      request.emit('end')
    })
  })
}

try {
  const bridge = await import(`./lib/index.js?verify=${Date.now()}`)
  bridge.apply(ctx)
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(desktopEvents.some((event) => event.type === 'bridge.connected'), true)
  assert.equal(desktopEvents.find((event) => event.type === 'bridge.connected').id, `bridge-connected-${process.pid}`)

  const status = await invoke('/dsh-desktop-bridge/status')
  assert.equal(status.status, 200)
  assert.equal(JSON.parse(status.body).ok, true)

  hooks.get('session/event')[0](agent.session, {
    type: 'step/start', seq: 42, data: { turn: 0, step: 1 },
  })
  await new Promise((resolve) => setTimeout(resolve, 0))
  const progress = desktopEvents.find((event) => event.type === 'task.progress')
  assert.equal(progress.id, 'task-progress-session-verify-42')
  assert.equal(progress.message, '已进入处理步骤 2。')

  const prompt = await invoke('/dsh-desktop-bridge/prompt', { protocolVersion: 1, prompt: 'verify prompt' })
  assert.equal(prompt.status, 202)
  assert.equal(followup.role, 'user')
  assert.equal(followup.content[0].text, 'verify prompt')

  agent.session.events = [{ type: 'approval/asked', data: { id: 'approval-id', callId: 'call-id' } }]
  const approvalHandler = hooks.get('approval/request')[0]
  const request = { agent, toolName: 'bash', callId: 'call-id', signal: new AbortController().signal }
  const allowedPromise = approvalHandler(request, async () => 'web-fallback')
  await new Promise((resolve) => setTimeout(resolve, 0))
  const allowed = await invoke('/dsh-desktop-bridge/approval', {
    protocolVersion: 1, eventId: 'approval-approval-id', outcome: 'allowed-once',
  })
  assert.equal(allowed.status, 200)
  assert.equal(await allowedPromise, 'allowed-once')

  agent.session.events = [{ type: 'approval/asked', data: { id: 'approval-defer', callId: 'call-defer' } }]
  const deferPromise = approvalHandler({ ...request, callId: 'call-defer' }, async () => 'web-fallback')
  await new Promise((resolve) => setTimeout(resolve, 0))
  await invoke('/dsh-desktop-bridge/approval', {
    protocolVersion: 1, eventId: 'approval-approval-defer', outcome: 'defer-to-web',
  })
  assert.equal(await deferPromise, 'web-fallback')

  desktopAvailable = false
  agent.session.events = [{ type: 'approval/asked', data: { id: 'approval-offline', callId: 'call-offline' } }]
  assert.equal(await approvalHandler({ ...request, callId: 'call-offline' }, async () => 'web-fallback'), 'web-fallback')

  console.log('Harness bridge verification passed: durable progress, prompt, native approval, Web fallback and offline fallback')
} finally {
  for (const dispose of disposers.reverse()) dispose()
  rmSync(root, { recursive: true, force: true })
}
