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
let createdOptions = null
const resolved = []
const agents = new Map()
for (const [id, cwd] of [['session-old', '/work/old'], ['session-new', '/work/new']]) {
  agents.set(id, {
    id, status: 'idle', session: { id, header: { id, cwd }, events: [] },
    followup(message) { followup = { id, message } },
  })
}
const records = [...agents.values()].reverse().map(({ session }) => ({ header: session.header, live: true, persisted: true }))
records.push({ header: { id: 'session-cold', cwd: '/work/cold' }, live: false, persisted: true })
records.push({ header: { id: 'session-child', cwd: '/work/child', parentSession: 'session-old', origin: 'subagent' }, live: false, persisted: true })
records.push({ header: { id: 'session-fork', cwd: '/work/fork', parentSession: 'session-old' }, live: false, persisted: true })
const ctx = {
  agents: {
    list: () => [...agents.values()], get: (id) => agents.get(id),
    create: async (options) => {
      createdOptions = options
      const agent = { id: options.sessionId, status: 'idle', session: { id: options.sessionId, header: { id: options.sessionId, cwd: options.meta.cwd }, events: [] }, followup(message) { followup = { id: options.sessionId, message } } }
      agents.set(options.sessionId, agent)
      return { agent, dispose() {} }
    },
  },
  sessionQuery: {
    listSessions: async () => records,
    readTitleSnapshots: async (ids) => ids.map((sessionId) => ({ sessionId, status: 'fulfilled', value: { title: sessionId === 'session-cold' ? undefined : { title: sessionId === 'session-old' ? '旧会话' : sessionId === 'session-new' ? '新会话' : undefined } } })),
    readSession: async (id) => ({
      session: { id, cwd: `/work/${id}` }, inheritedEventCount: 0,
      events: [{ type: 'assistant/message', data: { message: { content: [{ type: 'text', text: `summary:${id}` }] } } }],
    }),
  },
  sessionController: {
    list: async () => ({ items: records.filter(({ header }) => header.cwd).map(({ header, live }) => ({
      sessionId: header.id, cwd: header.cwd, agentAvailable: live,
      ...(header.parentSession ? { parentSessionId: header.parentSession } : {}),
      ...(header.origin ? { origin: header.origin } : {}),
    })) }),
    resolveAgent: async (id) => {
      resolved.push(id)
      if (id === 'session-child') return { error: new Error('session is owned by subagent routing') }
      if (!agents.has(id)) {
        const agent = { id, status: 'idle', session: { id, header: { id, cwd: '/work/cold' }, events: [] }, followup(message) { followup = { id, message } } }
        agents.set(id, agent)
        return { agent }
      }
      return { agent: agents.get(id) }
    },
  },
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

  const statusHandler = hooks.get('agent/status')[0]
  const lifecycleAgent = agents.get('session-old')
  const beforeLifecycle = desktopEvents.length
  statusHandler({ agent: lifecycleAgent, status: 'running' })
  statusHandler({ agent: lifecycleAgent, status: 'idle' })
  statusHandler({ agent: lifecycleAgent, status: 'running' })
  hooks.get('agent/error')[0]({ agent: lifecycleAgent })
  statusHandler({ agent: lifecycleAgent, status: 'idle' })
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.deepEqual(desktopEvents.slice(beforeLifecycle).map(({ type, sessionId }) => [type, sessionId]), [
    ['task.started', 'session-old'], ['task.completed', 'session-old'],
    ['task.started', 'session-old'], ['task.failed', 'session-old'],
  ])

  const sessions = await invoke('/dsh-desktop-bridge/sessions')
  assert.deepEqual(JSON.parse(sessions.body).sessions.map(({ sessionId, title, cwd }) => [sessionId, title, cwd]), [
    ['session-new', '新会话', '/work/new'], ['session-old', '旧会话', '/work/old'], ['session-cold', 'session-cold', '/work/cold'],
    ['session-fork', 'session-fork', '/work/fork'],
  ])

  hooks.get('session/event')[0](agents.get('session-new').session, {
    type: 'step/start', seq: 42, data: { turn: 0, step: 1 },
  })
  await new Promise((resolve) => setTimeout(resolve, 0))
  const progress = desktopEvents.find((event) => event.type === 'task.progress')
  assert.equal(progress.id, 'task-progress-session-new-42')
  assert.equal(progress.message, '已进入处理步骤 2。')

  const summary = await invoke('/dsh-desktop-bridge/summary', { protocolVersion: 1, sessionId: 'session-old' })
  assert.equal(JSON.parse(summary.body).text, 'summary:session-old')

  const prompt = await invoke('/dsh-desktop-bridge/prompt', { protocolVersion: 1, prompt: 'verify prompt', sessionId: 'session-old' })
  assert.equal(prompt.status, 202)
  assert.equal(followup.id, 'session-old')
  assert.equal(followup.message.role, 'user')
  assert.equal(followup.message.content[0].text, 'verify prompt')

  const coldPrompt = await invoke('/dsh-desktop-bridge/prompt', { protocolVersion: 1, prompt: 'resume exact session', sessionId: 'session-cold' })
  assert.equal(coldPrompt.status, 202)
  assert.deepEqual(resolved, ['session-old', 'session-cold'])
  assert.equal(followup.id, 'session-cold')

  const beforeChildPrompt = followup
  const childPrompt = await invoke('/dsh-desktop-bridge/prompt', { protocolVersion: 1, prompt: 'do not resume child', sessionId: 'session-child' })
  assert.equal(childPrompt.status, 409)
  assert.equal(followup, beforeChildPrompt)

  const missingDirectory = await invoke('/dsh-desktop-bridge/prompt', { protocolVersion: 1, prompt: 'no directory', mode: 'new' })
  assert.equal(missingDirectory.status, 400)
  const newPrompt = await invoke('/dsh-desktop-bridge/prompt', { protocolVersion: 1, prompt: 'explicit directory', mode: 'new', cwd: tmpdir() })
  assert.equal(newPrompt.status, 202)
  assert.equal(createdOptions.meta.cwd, tmpdir())
  assert.notEqual(createdOptions.meta.cwd, agents.get('session-new').session.header.cwd)

  const agent = agents.get('session-new')
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

  console.log('Harness bridge verification passed: automatic task lifecycle notifications, explicit session list/summary/prompt, durable progress, native approval, Web fallback and offline fallback')
} finally {
  for (const dispose of disposers.reverse()) dispose()
  rmSync(root, { recursive: true, force: true })
}
