import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const bundle = readFileSync(new URL('../client/client.js', import.meta.url), 'utf8')

function fixture({ openSession = (id, sessions) => { sessions.select(id) }, selectPanel = () => {}, phase = 'ready' } = {}) {
  const messages = []
  const panelMessages = []
  const listeners = new Map()
  const timers = new Map()
  let nextTimer = 0
  let teardown
  const window = {
    webkit: { messageHandlers: {
      dshDesktopOpenSession: { postMessage: (message) => messages.push(message) },
      dshDesktopOpenPanel: { postMessage: (message) => panelMessages.push(message) },
    } },
    __ModuleLoader__: { load: (registration) => { window.__ModuleLoader__.registered = registration } },
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: (name) => listeners.delete(name),
    dispatchEvent: (event) => listeners.get(event.type)?.(event),
  }
  vm.runInNewContext(bundle, {
    window,
    setTimeout(callback) { const id = ++nextTimer; timers.set(id, callback); return id },
    clearTimeout(id) { timers.delete(id) },
  })
  const { factory } = window.__ModuleLoader__.registered
  const plugin = factory(() => { throw new Error('unexpected client import') })
  const state = {
    ids: ['task-42', 'slow'], phase, projectionsBySession: {},
    byId: {
      'task-42': { id: 'task-42', retainedBy: {} },
      slow: { id: 'slow', retainedBy: {} },
    },
  }
  const subscriptions = new Set()
  const sessions = {
    list: {
      getSnapshot: () => state,
      subscribe(callback) { subscriptions.add(callback); return () => subscriptions.delete(callback) },
    },
    select(id) {
      for (const row of Object.values(state.byId)) row.retainedBy.mainView = row.id === id ? 1 : 0
      for (const callback of subscriptions) callback()
    },
    ready() { state.phase = 'ready'; for (const callback of subscriptions) callback() },
  }
  const ctx = {
    uiWorkspace: { openSession: (id) => openSession(id, sessions) },
    layout: { selectPanel },
    sessions,
    effect(callback) { teardown = callback() },
  }
  plugin.apply(ctx)
  return {
    messages, panelMessages, timers, sessions, window,
    open(sessionId) { window.dispatchEvent({ type: 'dsh-desktop-open-session', detail: { sessionId } }) },
    openPanel(panelId) { window.dispatchEvent({ type: 'dsh-desktop-open-panel', detail: { panelId } }) },
    expire() { for (const callback of timers.values()) callback() },
    close() { teardown?.() },
  }
}

test('acknowledges only after the official workspace navigation selects the requested session', () => {
  const page = fixture()
  assert.equal(page.messages[0].ready, true)
  page.open('task-42')
  assert.equal(page.sessions.list.getSnapshot().byId['task-42'].retainedBy.mainView, 1)
  assert.equal(page.messages.at(-1).sessionId, 'task-42')
  assert.equal(page.messages.at(-1).opened, true)
})

test('reports a missing session through the native bridge', () => {
  const page = fixture({ openSession: () => { throw new Error('unknown session') } })
  page.open('gone')
  assert.equal(page.messages.at(-1).sessionId, 'gone')
  assert.equal(page.messages.at(-1).opened, false)
  assert.match(page.messages.at(-1).error, /侧栏/u)
})

test('ends an unresolved navigation with a visible timeout error', () => {
  const page = fixture({ openSession: () => {} })
  page.open('slow')
  assert.equal(page.messages.length, 1)
  assert.equal(page.messages[0].ready, true)
  page.expire()
  assert.equal(page.messages.at(-1).opened, false)
  assert.match(page.messages.at(-1).error, /超时/u)
})

test('waits for the official catalog before selecting a session during startup', () => {
  const page = fixture({ phase: 'pending' })
  page.open('task-42')
  assert.equal(page.messages.length, 1)
  page.sessions.ready()
  assert.equal(page.messages.at(-1).opened, true)
})

test('selects the official plugins panel and acknowledges the native request', async () => {
  const selected = []
  const page = fixture({ selectPanel: (id) => selected.push(id) })
  assert.equal(page.panelMessages[0]?.ready, true)
  page.openPanel('plugins')
  await Promise.resolve()
  assert.deepEqual(selected, ['plugins'])
  assert.equal(page.panelMessages.at(-1).panelId, 'plugins')
  assert.equal(page.panelMessages.at(-1).opened, true)
})

test('rejects unsupported workspace panel requests', () => {
  const selected = []
  const page = fixture({ selectPanel: (id) => selected.push(id) })
  page.openPanel('settings')
  assert.deepEqual(selected, [])
  assert.equal(page.panelMessages.at(-1)?.opened, false)
  assert.match(page.panelMessages.at(-1)?.error ?? '', /面板/u)
})

test('reports when the official workspace panel selection fails', async () => {
  const page = fixture({ selectPanel: () => Promise.reject(new Error('panel unavailable')) })
  page.openPanel('plugins')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(page.panelMessages.at(-1)?.opened, false)
  assert.match(page.panelMessages.at(-1)?.error ?? '', /插件/u)
})
