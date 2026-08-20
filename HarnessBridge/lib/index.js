import { randomUUID } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const name = 'dsh-desktop-bridge'
export const inject = ['webServer', 'agents']

const DSH_HOME = process.env.DSH_HOME ?? join(homedir(), '.dsh')
const TOKEN_FILE = join(DSH_HOME, 'desktop-bridge', 'token')
const DESKTOP_BASE = process.env.DSH_DESKTOP_BRIDGE_URL ?? 'http://127.0.0.1:3091'
const HOST = process.env.DSH_WEB_HOST ?? '127.0.0.1'
const PORT = process.env.DSH_WEB_PORT ?? '3080'
const CALLBACK = `http://127.0.0.1:${PORT}/dsh-desktop-bridge/approval`
const PROTOCOL_VERSION = 1

function readToken() {
  try { return readFileSync(TOKEN_FILE, 'utf8').trim() } catch { return '' }
}

async function postDesktop(event) {
  const token = readToken()
  if (token.length < 32) return false
  try {
    const response = await fetch(`${DESKTOP_BASE}/v1/events`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ protocolVersion: PROTOCOL_VERSION, ...event }),
      signal: AbortSignal.timeout(2500),
    })
    return response.ok
  } catch { return false }
}

function sendJson(response, status, value) {
  const body = JSON.stringify(value)
  response.writeHead(status, {
    'cache-control': 'no-store',
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  })
  response.end(body)
}

function readJsonBody(request) {
  return new Promise((resolve) => {
    const chunks = []
    let size = 0
    request.on('data', (chunk) => {
      size += chunk.length
      if (size > 16 * 1024) { request.destroy(); resolve(null); return }
      chunks.push(chunk)
    })
    request.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')) } catch { resolve(null) }
    })
    request.on('error', () => resolve(null))
  })
}

function authorized(request) {
  const token = readToken()
  return token.length >= 32 && request.headers.authorization === `Bearer ${token}`
}

function userMessage(text) {
  return Object.freeze({
    id: randomUUID(), role: 'user', source: { kind: 'user' },
    content: [Object.freeze({ type: 'text', text })],
  })
}

function approvalId(req) {
  const decided = new Set()
  for (let index = req.agent.session.events.length - 1; index >= 0; index -= 1) {
    const event = req.agent.session.events[index]
    if (event.type === 'approval/decided') decided.add(event.data.id)
    if (event.type !== 'approval/asked' || decided.has(event.data.id)) continue
    if ((req.callId ?? null) === (event.data.callId ?? null)) return String(event.data.id)
  }
  return randomUUID()
}

export function apply(ctx) {
  ctx.effect(() => {
    const pending = new Map()
    const agents = new Map()
    const running = new Set()
    const failed = new Set()
    let latestAgent = null
    const disposers = []

    for (const agent of ctx.agents.list()) {
      agents.set(String(agent.id), agent)
      latestAgent = String(agent.id)
      if (agent.status === 'running') running.add(String(agent.id))
    }

    const route = (path, handler) => {
      disposers.push(ctx.webServer.register({
        kind: 'exact', path,
        handler: async (request, response) => {
          try { await handler(request, response) }
          catch (error) { sendJson(response, 500, { ok: false, error: String(error?.message ?? error) }) }
        },
      }))
    }

    route('/dsh-desktop-bridge/status', async (_request, response) => {
      sendJson(response, 200, { ok: true, protocolVersion: PROTOCOL_VERSION, desktopReachable: existsSync(TOKEN_FILE) })
    })

    route('/dsh-desktop-bridge/prompt', async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, { ok: false, error: 'method not allowed' })
      if (!authorized(request)) return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      const body = await readJsonBody(request)
      const prompt = typeof body?.prompt === 'string' ? body.prompt.trim() : ''
      if (body?.protocolVersion !== PROTOCOL_VERSION || prompt.length === 0 || prompt.length > 32_000) {
        return sendJson(response, 400, { ok: false, error: 'invalid prompt' })
      }
      const agent = latestAgent !== null ? agents.get(latestAgent) : undefined
      if (agent === undefined) return sendJson(response, 409, { ok: false, error: 'no active Harness session' })
      agent.followup(userMessage(prompt))
      sendJson(response, 202, { ok: true, sessionId: String(agent.id) })
    })

    route('/dsh-desktop-bridge/approval', async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, { ok: false, error: 'method not allowed' })
      if (!authorized(request)) return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      const body = await readJsonBody(request)
      const item = pending.get(body?.eventId)
      if (item === undefined) return sendJson(response, 409, { ok: false, error: 'approval is no longer pending' })
      if (!['allowed-once', 'rejected', 'defer-to-web'].includes(body?.outcome)) {
        return sendJson(response, 400, { ok: false, error: 'invalid outcome' })
      }
      pending.delete(body.eventId)
      item.resolve(body.outcome)
      sendJson(response, 200, { ok: true })
    })

    disposers.push(ctx.on('agent/created', ({ agent }) => {
      agents.set(String(agent.id), agent)
      latestAgent = String(agent.id)
    }))
    disposers.push(ctx.on('agent/disposed', ({ agent }) => {
      const id = String(agent.id)
      agents.delete(id); running.delete(id); failed.delete(id)
      if (latestAgent === id) latestAgent = [...agents.keys()].at(-1) ?? null
    }))
    disposers.push(ctx.on('agent/status', ({ agent, status }) => {
      const sessionId = String(agent.id)
      latestAgent = sessionId
      if (status === 'running') {
        running.add(sessionId); failed.delete(sessionId)
        void postDesktop({ id: `task-started-${randomUUID()}`, type: 'task.started', title: '任务已开始', message: 'Harness 正在处理任务。', sessionId })
      } else if (running.delete(sessionId) && !failed.delete(sessionId)) {
        void postDesktop({ id: `task-completed-${randomUUID()}`, type: 'task.completed', title: '任务已完成', message: 'Harness 已完成当前任务。', sessionId })
      }
    }))
    disposers.push(ctx.on('agent/error', ({ agent }) => {
      const sessionId = String(agent.id)
      failed.add(sessionId)
      void postDesktop({ id: `task-failed-${randomUUID()}`, type: 'task.failed', title: '任务执行失败', message: 'Harness 任务执行失败，请打开客户端查看详情。', sessionId })
    }))

    // Prepend so the native answerer gets first refusal. If the desktop is not
    // reachable, or the user chooses “open task”, next() restores the official
    // Web approval provider instead of failing open.
    disposers.push(ctx.on('approval/request', async (req, next) => {
      if (req.signal?.aborted) return 'cancelled'
      const eventId = `approval-${approvalId(req)}`
      let settle
      const decision = new Promise((resolve) => { settle = resolve })
      const finish = (value) => {
        req.signal?.removeEventListener('abort', abort)
        settle(value)
      }
      const abort = () => { pending.delete(eventId); finish('cancelled') }
      pending.set(eventId, { resolve: finish })
      req.signal?.addEventListener('abort', abort, { once: true })
      const delivered = await postDesktop({
        id: eventId, type: 'approval.requested', title: 'Harness 需要你的批准',
        message: `工具 ${req.toolName} 请求执行受限操作。`,
        sessionId: String(req.agent.session.id), callbackURL: CALLBACK,
      })
      if (!delivered) {
        pending.delete(eventId)
        req.signal?.removeEventListener('abort', abort)
        return req.signal?.aborted ? 'cancelled' : next()
      }
      const outcome = await decision
      return outcome === 'defer-to-web' ? next() : outcome
    }, { prepend: true }))

    const announce = () => void postDesktop({
      id: `bridge-connected-${process.pid}`, type: 'bridge.connected',
      title: 'Harness 已连接', message: '原生控制面已连接。',
      promptURL: `http://127.0.0.1:${PORT}/dsh-desktop-bridge/prompt`,
    })
    announce()
    const reconnectTimer = setInterval(announce, 15_000)

    return () => {
      clearInterval(reconnectTimer)
      for (const item of pending.values()) item.resolve('cancelled')
      pending.clear()
      for (const dispose of disposers.reverse()) dispose()
    }
  })
}
