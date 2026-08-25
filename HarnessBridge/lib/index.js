import { randomUUID } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const name = 'dsh-desktop-bridge'
export const inject = ['webServer', 'agents', 'llm']

const DSH_HOME = process.env.DSH_HOME ?? join(homedir(), '.dsh')
const TOKEN_FILE = join(DSH_HOME, 'desktop-bridge', 'token')
const DESKTOP_BASE = process.env.DSH_DESKTOP_BRIDGE_URL ?? 'http://127.0.0.1:3091'
const HOST = process.env.DSH_WEB_HOST ?? '127.0.0.1'
const PORT = process.env.DSH_WEB_PORT ?? '3080'
const CALLBACK = `http://127.0.0.1:${PORT}/dsh-desktop-bridge/approval`
const PROTOCOL_VERSION = 1
const EFFORTS = new Set(['off', 'low', 'high', 'max'])

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

/** 取最后一条 assistant 消息的文本末尾 lineCount 行（用于「已有会话」摘要）。 */
function lastAssistantText(events, lineCount = 20) {
  for (let index = events.length - 1; index >= 0; index -= 1) {
    const event = events[index]
    if (event?.type !== 'assistant/message') continue
    const message = event.data?.message
    if (!message || !Array.isArray(message.content)) continue
    const text = message.content
      .filter((block) => block?.type === 'text' && typeof block.text === 'string')
      .map((block) => block.text)
      .join('\n')
    if (!text.trim()) continue
    return text.split('\n').slice(-lineCount).join('\n')
  }
  return ''
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

    route('/dsh-desktop-bridge/models', async (request, response) => {
      if (request.method !== 'GET') return sendJson(response, 405, { ok: false, error: 'method not allowed' })
      if (!authorized(request)) return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      const models = []
      for (const provider of ctx.llm.listProviders()) {
        const list = await ctx.llm.listModels(provider.id)
        for (const model of list) models.push({ provider: provider.id, model: model.id, name: model.name || model.id })
      }
      sendJson(response, 200, { ok: true, models })
    })

    route('/dsh-desktop-bridge/summary', async (request, response) => {
      if (request.method !== 'GET') return sendJson(response, 405, { ok: false, error: 'method not allowed' })
      if (!authorized(request)) return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      const agent = latestAgent !== null ? agents.get(latestAgent) : undefined
      if (agent === undefined) return sendJson(response, 409, { ok: false, error: 'no active Harness session' })
      sendJson(response, 200, { ok: true, text: lastAssistantText(agent.session?.events ?? [], 20) })
    })

    route('/dsh-desktop-bridge/prompt', async (request, response) => {
      if (request.method !== 'POST') return sendJson(response, 405, { ok: false, error: 'method not allowed' })
      if (!authorized(request)) return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      const body = await readJsonBody(request)
      const prompt = typeof body?.prompt === 'string' ? body.prompt.trim() : ''
      if (body?.protocolVersion !== PROTOCOL_VERSION || prompt.length === 0 || prompt.length > 32_000) {
        return sendJson(response, 400, { ok: false, error: 'invalid prompt' })
      }
      const currentAgent = latestAgent !== null ? agents.get(latestAgent) : undefined

      // 新会话：独立创建一个 agent（默认继承当前会话的工作目录）。
      // 仅显式 new 才新开；旧客户端不传 mode，保持「已有会话」原行为。
      if (body?.mode === 'new') {
        const cwd = currentAgent?.session?.header?.cwd ?? currentAgent?.session?.cwd
        const fallback = (() => { try { return ctx.agentDefaultModel?.currentSelection?.() ?? null } catch { return null } })()
        const provider = typeof body?.provider === 'string' && body.provider ? body.provider : (fallback?.provider ?? undefined)
        const model = typeof body?.model === 'string' && body.model ? body.model : (fallback?.model ?? undefined)
        const effort = typeof body?.effort === 'string' && EFFORTS.has(body.effort) ? body.effort : undefined
        const hasModel = Boolean(provider && model)
        const handle = await ctx.agents.create({
          sessionId: randomUUID(),
          agentOptions: hasModel ? { provider, model } : undefined,
          meta: cwd ? { cwd } : undefined,
          // 力度通过 agent 作用域的 agent/request 瀑布覆盖（profile 插件不能 import 引擎核心包）。
          setup: effort ? (agentCtx) => {
            agentCtx.on('agent/request', async (_payload, next) => {
              const config = await next()
              return { ...config, reasoningEffort: effort }
            })
          } : undefined,
        })
        handle.agent.followup(userMessage(prompt))
        return sendJson(response, 202, { ok: true, sessionId: String(handle.agent.id), mode: 'new' })
      }

      // 已有会话：延续当前活动会话。
      if (currentAgent === undefined) return sendJson(response, 409, { ok: false, error: 'no active Harness session' })
      currentAgent.followup(userMessage(prompt))
      sendJson(response, 202, { ok: true, sessionId: String(currentAgent.id), mode: 'existing' })
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
    // `session/event` is Harness's durable, versioned event stream. A step/start
    // is a real processing boundary, so it can report progress without reading
    // logs, inspecting message contents, or guessing from Web UI state.
    disposers.push(ctx.on('session/event', (session, event) => {
      const sessionId = String(session.id)
      if (!agents.has(sessionId) || event?.type !== 'step/start') return
      const step = Number(event.data?.step)
      if (!Number.isInteger(step) || step < 0 || !Number.isInteger(event.seq)) return
      void postDesktop({
        id: `task-progress-${sessionId}-${event.seq}`,
        type: 'task.progress',
        title: '任务正在处理',
        message: `已进入处理步骤 ${step + 1}。`,
        sessionId,
      })
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
