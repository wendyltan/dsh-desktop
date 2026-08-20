#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process'
import {
  closeSync, copyFileSync, cpSync, existsSync, mkdirSync, openSync, readFileSync,
  lstatSync, readlinkSync, readdirSync, realpathSync, renameSync, rmSync, statSync,
  symlinkSync, unlinkSync, writeFileSync,
} from 'node:fs'
import { createServer } from 'node:net'
import { createHash } from 'node:crypto'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HOME = homedir()
const DSH_HOME = process.env.DSH_HOME ?? join(HOME, '.dsh')
const ROOT = join(DSH_HOME, 'guardian')
const PROFILE = join(DSH_HOME, 'profiles', 'web')
const SAFE_PROFILE = join(DSH_HOME, 'profiles', 'safe')
const LKG = join(ROOT, 'last-known-good')
const STATE_FILE = join(ROOT, 'state.json')
const ENABLED_FILE = join(ROOT, 'enabled')
const MAINTENANCE_FILE = join(ROOT, 'maintenance')
const LOCK_DIR = join(ROOT, '.lock')
const LOG_DIR = join(DSH_HOME, 'logs')
const LOG_FILE = join(LOG_DIR, 'dsh-web.log')
const PID_FILE = join(LOG_DIR, 'dsh-web.pid')
const GUARDIAN_LOG = join(LOG_DIR, 'dsh-guardian.log')
const HOST = process.env.DSH_WEB_HOST ?? '127.0.0.1'
const PORT = Number(process.env.DSH_WEB_PORT ?? 3080)
const BASE = `http://${HOST}:${PORT}`
const command = process.argv[2] ?? 'status'
const wantsJson = process.argv.includes('--json')
const GUARDIAN_VERSION = '0.3.0'
const PROTOCOL_VERSION = 2
const CAPABILITIES = ['status', 'preflight', 'start', 'restart', 'recover', 'safe-mode', 'watchdog', 'snapshot', 'integrations', 'diff']
const PROFILE_FILES = ['package.json', 'cordis.yml', 'cordis.patch.yml']

mkdirSync(ROOT, { recursive: true })
mkdirSync(LOG_DIR, { recursive: true })

function now() { return new Date().toISOString() }
function log(message) {
  const line = `[${now()}] ${message}\n`
  writeFileSync(GUARDIAN_LOG, line, { flag: 'a' })
  if (!wantsJson) process.stdout.write(line)
}
function output(value) {
  process.stdout.write(JSON.stringify(value, null, wantsJson ? 0 : 2) + '\n')
}
function readJson(file, fallback = null) {
  try { return JSON.parse(readFileSync(file, 'utf8')) } catch { return fallback }
}
function writeJsonAtomic(file, value) {
  const temp = `${file}.new`
  writeFileSync(temp, JSON.stringify(value, null, 2) + '\n')
  renameSync(temp, file)
}
function state() {
  return readJson(STATE_FILE, { mode: 'unknown', failures: [], lastSuccess: null, lastError: null })
}
function updateState(patch) { writeJsonAtomic(STATE_FILE, { ...state(), ...patch, updatedAt: now() }) }
function profileBundles(profile = PROFILE) {
  return readJson(join(profile, 'package.json'), {})?.dsh?.profile?.bundles ?? []
}
function bundlePackage(profile, id) {
  const packageFile = join(profile, 'node_modules', ...id.split('/'), 'package.json')
  return { packageFile, pkg: readJson(packageFile), bundleDir: dirname(packageFile) }
}

/** Optional integrations are declared by each bundle in package.json:
 *  dsh.guardian.healthPath verifies its host route; snapshotLinkedBundle asks
 *  Guardian to include an internal-disk linked deployment in the LKG snapshot.
 *  Guardian therefore has no repository-specific names, paths, or endpoints. */
function guardianIntegrations(profile = PROFILE) {
  const integrations = []
  for (const id of profileBundles(profile)) {
    const { pkg, bundleDir } = bundlePackage(profile, id)
    const declared = pkg?.dsh?.guardian
    if (declared === null || typeof declared !== 'object' || Array.isArray(declared)) continue
    let target = null
    try { target = realpathSync(bundleDir) } catch {}
    integrations.push({
      id,
      protocolVersion: Number(declared.protocolVersion ?? 0),
      healthPath: typeof declared.healthPath === 'string' && /^\/(?!\/)/.test(declared.healthPath)
        ? declared.healthPath : null,
      snapshotLinkedBundle: declared.snapshotLinkedBundle === true,
      profileFiles: Array.isArray(declared.profileFiles)
        ? declared.profileFiles.filter((name) => typeof name === 'string' && /^[A-Za-z0-9._-]+$/.test(name))
        : [],
      target,
    })
  }
  return integrations
}

function isInsideDshHome(path) {
  let base = resolve(DSH_HOME)
  let target = resolve(path)
  try { base = realpathSync(base) } catch {}
  try { target = realpathSync(target) } catch {
    try { target = join(realpathSync(dirname(target)), target.split('/').pop()) } catch {}
  }
  return target === base || target.startsWith(base + '/')
}

function acquireLock() {
  try { mkdirSync(LOCK_DIR); writeFileSync(join(LOCK_DIR, 'pid'), String(process.pid)); return true } catch {}
  try {
    if (Date.now() - statSync(LOCK_DIR).mtimeMs > 300_000) {
      rmSync(LOCK_DIR, { recursive: true, force: true })
      mkdirSync(LOCK_DIR)
      writeFileSync(join(LOCK_DIR, 'pid'), String(process.pid))
      return true
    }
  } catch {}
  return false
}
function releaseLock() { rmSync(LOCK_DIR, { recursive: true, force: true }) }

function resolveDshBin() {
  const candidates = [join(PROFILE, 'node_modules', '.bin', 'dsh')]
  const npxRoot = join(HOME, '.npm', '_npx')
  try {
    const caches = readdirSync(npxRoot)
      .map((name) => join(npxRoot, name, 'node_modules', '.bin', 'dsh'))
      .filter(existsSync)
      .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs)
    candidates.push(...caches)
  } catch {}
  const which = spawnSync('which', ['dsh'], { encoding: 'utf8' })
  if (which.status === 0 && which.stdout.trim()) candidates.push(which.stdout.trim())
  const found = candidates.find(existsSync)
  if (!found) throw new Error('cannot resolve dsh executable')
  return found
}
function dshEntry() { return realpathSync(resolveDshBin()) }

/** 从实际启动的 dsh 二进制向上定位 @deepseek-ai/dsh/package.json，读取引擎版本。
 *  与 dsh-ops-console 无关：只依赖 Guardian 自己 resolveDshBin() 的结果。
 *  解析失败返回 null，由调用方自行回退。 */
function detectEngineVersion() {
  try {
    let dir = dirname(dshEntry())
    for (let i = 0; i < 12 && dir; i++) {
      try {
        const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))
        if (pkg.name === '@deepseek-ai/dsh' && typeof pkg.version === 'string' && pkg.version !== '') {
          return pkg.version
        }
      } catch { /* keep walking up */ }
      const parent = dirname(dir)
      if (parent === dir) break
      dir = parent
    }
  } catch { /* dsh 不可解析 */ }
  return null
}

function copyProfileFiles(source, destination, { prune = false, extraFiles = [] } = {}) {
  mkdirSync(destination, { recursive: true })
  for (const name of new Set([...PROFILE_FILES, ...extraFiles])) {
    const src = join(source, name)
    const dest = join(destination, name)
    if (existsSync(src)) copyFileSync(src, dest)
    else if (prune) rmSync(dest, { force: true })
  }
}

function makeScratch(profile = PROFILE) {
  const scratch = join(ROOT, 'tmp', `check-${process.pid}-${Date.now()}`)
  const scratchProfile = join(scratch, 'profiles', 'web')
  const extraFiles = guardianIntegrations(profile).flatMap((item) => item.profileFiles)
  copyProfileFiles(profile, scratchProfile, { extraFiles })
  const modules = join(profile, 'node_modules')
  if (!existsSync(modules)) throw new Error(`profile node_modules missing: ${modules}`)
  symlinkSync(modules, join(scratchProfile, 'node_modules'), 'dir')
  return { scratch, scratchProfile }
}

function validateProfileFiles(profile = PROFILE) {
  const issues = []
  const packageFile = join(profile, 'package.json')
  const pkg = readJson(packageFile)
  if (!pkg) issues.push(`invalid JSON: ${packageFile}`)
  const bundles = pkg?.dsh?.profile?.bundles
  if (!Array.isArray(bundles) || bundles.length === 0) issues.push('dsh.profile.bundles must be a non-empty array')
  if (new Set(bundles ?? []).size !== (bundles ?? []).length) issues.push('duplicate bundle ids in profile')
  const entry = dshEntry()
  const modulesMarker = '/node_modules/'
  const markerAt = entry.lastIndexOf(modulesMarker)
  const runtimeModules = markerAt < 0 ? null : entry.slice(0, markerAt + modulesMarker.length - 1)
  for (const id of bundles ?? []) {
    const parts = id.split('/')
    const profilePackage = join(profile, 'node_modules', ...parts, 'package.json')
    const runtimePackage = runtimeModules === null ? '' : join(runtimeModules, ...parts, 'package.json')
    if (!existsSync(profilePackage) && !existsSync(runtimePackage)) issues.push(`bundle package missing: ${id}`)
  }
  for (const id of bundles ?? []) {
    const bundleDir = join(profile, 'node_modules', ...id.split('/'))
    try {
      if (!lstatSync(bundleDir).isSymbolicLink()) continue
      const target = realpathSync(bundleDir)
      if (target.startsWith('/Volumes/')) issues.push(`live bundle ${id} depends on external volume: ${target}`)
    } catch { /* package existence was checked above */ }
  }
  const integrations = guardianIntegrations(profile)
  for (const item of integrations) {
    if (item.protocolVersion !== 1) issues.push(`unsupported guardian integration protocol for ${item.id}: ${item.protocolVersion}`)
    if (item.snapshotLinkedBundle && (item.target === null || !isInsideDshHome(item.target))) {
      issues.push(`guardian snapshot target must be inside DSH_HOME: ${item.id}`)
    }
  }
  return { ok: issues.length === 0, issues, bundles: bundles ?? [], integrations }
}

function dumpConfigCheck() {
  const { scratch } = makeScratch()
  try {
    const result = spawnSync(process.execPath, [dshEntry(), '--profile', 'web', '--dump-config'], {
      env: { ...process.env, DSH_HOME: scratch }, encoding: 'utf8', timeout: 60_000,
    })
    if (result.status !== 0) throw new Error((result.stderr || result.stdout || 'dsh --dump-config failed').trim())
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
}

async function freePort() {
  return await new Promise((accept, reject) => {
    const server = createServer()
    server.once('error', reject)
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port
      server.close(() => accept(port))
    })
  })
}

function bootManifest(html) {
  const match = html.match(/window\.__DSH_BOOT__\s*=\s*(\{.*?\})\s*<\/script>/s)
  if (!match) throw new Error('boot manifest missing')
  return JSON.parse(match[1])
}

async function health(base, { healthPaths = [], checkBundles = true } = {}) {
  const root = await fetch(`${base}/`, { signal: AbortSignal.timeout(8_000) })
  if (!root.ok) throw new Error(`root HTTP ${root.status}`)
  const boot = bootManifest(await root.text())
  if (checkBundles) {
    for (const entry of boot.entries) {
      const response = await fetch(new URL(entry.url, base), { signal: AbortSignal.timeout(10_000) })
      if (!response.ok) throw new Error(`${entry.id} HTTP ${response.status}`)
      const body = await response.text()
      if (!body.includes('window.__ModuleLoader__.load')) throw new Error(`${entry.id} registration missing`)
    }
  }
  for (const path of healthPaths) {
    const url = new URL(path, base)
    if (url.origin !== new URL(base).origin) throw new Error(`integration health must stay same-origin: ${path}`)
    const response = await fetch(url, { signal: AbortSignal.timeout(5_000) })
    let body = null
    try { body = await response.json() } catch {}
    if (!response.ok || body?.ok !== true) throw new Error(`integration health failed: ${path}`)
  }
  return { bootRev: boot.rev, modules: boot.entries.length }
}

async function preflight({ smoke = true } = {}) {
  const basic = validateProfileFiles()
  if (!basic.ok) return { ok: false, stage: 'files', ...basic }
  try { dumpConfigCheck() } catch (error) { return { ok: false, stage: 'compose', issues: [String(error.message ?? error)] } }
  if (!smoke) return { ok: true, stage: 'compose', bundles: basic.bundles }
  const { scratch } = makeScratch()
  const port = await freePort()
  const out = openSync(join(ROOT, 'smoke.out.log'), 'a')
  const err = openSync(join(ROOT, 'smoke.err.log'), 'a')
  const child = spawn(process.execPath, [dshEntry(), '--profile', 'web', '--host', '127.0.0.1', '--port', String(port)], {
    env: { ...process.env, DSH_HOME: scratch }, stdio: ['ignore', out, err],
  })
  closeSync(out)
  closeSync(err)
  try {
    const deadline = Date.now() + 75_000
    let lastError = 'not ready'
    while (Date.now() < deadline && child.exitCode === null) {
      try {
        const result = await health(`http://127.0.0.1:${port}`, {
          healthPaths: basic.integrations.map((item) => item.healthPath).filter(Boolean),
        })
        return { ok: true, stage: 'smoke', port, ...result, bundles: basic.bundles }
      } catch (error) { lastError = String(error.message ?? error) }
      await new Promise((accept) => setTimeout(accept, 500))
    }
    return { ok: false, stage: 'smoke', issues: [lastError, `exit=${child.exitCode ?? 'running'}`] }
  } finally {
    if (child.exitCode === null) child.kill('SIGTERM')
    await new Promise((accept) => setTimeout(accept, 600))
    if (child.exitCode === null) child.kill('SIGKILL')
    rmSync(scratch, { recursive: true, force: true })
  }
}

function snapshot() {
  const temp = `${LKG}.new`
  rmSync(temp, { recursive: true, force: true })
  mkdirSync(temp, { recursive: true })
  const integrations = guardianIntegrations()
  const profileFiles = [...new Set(integrations.flatMap((item) => item.profileFiles))]
  copyProfileFiles(PROFILE, join(temp, 'profile'), { extraFiles: profileFiles })
  const savedIntegrations = []
  mkdirSync(join(temp, 'integrations'), { recursive: true })
  for (const item of integrations) {
    if (!item.snapshotLinkedBundle || item.target === null || !isInsideDshHome(item.target)) continue
    const snapshotName = Buffer.from(item.id).toString('base64url')
    cpSync(item.target, join(temp, 'integrations', snapshotName), { recursive: true })
    savedIntegrations.push({ id: item.id, target: item.target, snapshotName })
  }
  writeJsonAtomic(join(temp, 'manifest.json'), {
    createdAt: now(), profile: 'web', profileFiles, integrations: savedIntegrations,
  })
  const previous = `${LKG}.previous`
  rmSync(previous, { recursive: true, force: true })
  if (existsSync(LKG)) renameSync(LKG, previous)
  renameSync(temp, LKG)
  updateState({ lastSnapshot: now() })
  return { ok: true, path: LKG, createdAt: now() }
}

function restoreLkg() {
  const savedProfile = join(LKG, 'profile')
  if (!existsSync(join(savedProfile, 'package.json'))) throw new Error('last-known-good profile is missing')
  const manifest = readJson(join(LKG, 'manifest.json'), {})
  const currentProfileFiles = guardianIntegrations().flatMap((item) => item.profileFiles)
  const profileFiles = [...new Set([...(manifest.profileFiles ?? []), ...currentProfileFiles])]
    .filter((name) => typeof name === 'string' && /^[A-Za-z0-9._-]+$/.test(name))
  copyProfileFiles(savedProfile, PROFILE, { prune: true, extraFiles: profileFiles })
  for (const item of manifest.integrations ?? []) {
    if (typeof item?.target !== 'string' || !isInsideDshHome(item.target)) continue
    if (typeof item.snapshotName !== 'string' || !/^[A-Za-z0-9_-]+$/.test(item.snapshotName)) continue
    const saved = join(LKG, 'integrations', String(item.snapshotName ?? ''))
    if (!existsSync(saved)) continue
    const temp = `${item.target}.recover`
    rmSync(temp, { recursive: true, force: true })
    cpSync(saved, temp, { recursive: true })
    const failed = `${item.target}.failed-${Date.now()}`
    if (existsSync(item.target)) renameSync(item.target, failed)
    renameSync(temp, item.target)
  }
  updateState({ lastRecovery: now() })
  return { ok: true, restored: LKG }
}

function digestFile(file) {
  try {
    const bytes = readFileSync(file)
    return { kind: 'file', digest: createHash('sha256').update(bytes).digest('hex'), size: bytes.length }
  } catch (error) {
    return { kind: 'unreadable', error: String(error?.code ?? error?.message ?? error) }
  }
}

function collectTree(root, prefix = '') {
  const result = new Map()
  if (!existsSync(root)) return result
  const walk = (directory, relative) => {
    let names
    try { names = readdirSync(directory).sort() } catch (error) {
      result.set(relative || '.', { kind: 'unreadable', error: String(error?.code ?? error?.message ?? error) })
      return
    }
    for (const name of names) {
      const absolute = join(directory, name)
      const child = relative ? join(relative, name) : name
      try {
        const info = lstatSync(absolute)
        if (info.isDirectory()) walk(absolute, child)
        else if (info.isSymbolicLink()) result.set(child, { kind: 'link', target: readlinkSync(absolute) })
        else if (info.isFile()) result.set(child, digestFile(absolute))
      } catch (error) {
        result.set(child, { kind: 'unreadable', error: String(error?.code ?? error?.message ?? error) })
      }
    }
  }
  walk(root, prefix)
  return result
}

function sameEntry(left, right) {
  if (left?.kind !== right?.kind) return false
  if (left?.kind === 'file') return left.digest === right.digest && left.size === right.size
  if (left?.kind === 'link') return left.target === right.target
  return left?.error === right?.error
}

function compareTrees(current, golden, scope) {
  const items = []
  const paths = [...new Set([...current.keys(), ...golden.keys()])].sort()
  for (const path of paths) {
    const live = current.get(path)
    const saved = golden.get(path)
    let status
    if (live === undefined) status = 'deleted'
    else if (saved === undefined) status = 'added'
    else if (live.kind === 'unreadable' || saved.kind === 'unreadable') status = 'unreadable'
    else if (!sameEntry(live, saved)) status = 'modified'
    else continue
    items.push({ scope, path, status })
  }
  return items
}

/** Return metadata-only drift against last-known-good. File contents and
 * digests never leave Guardian, so secret-bearing config remains private. */
function configDiff() {
  if (!existsSync(LKG)) return { ok: true, available: false, changed: false, summary: {}, items: [] }
  const manifest = readJson(join(LKG, 'manifest.json'), {})
  const profileFiles = [...new Set([...(manifest.profileFiles ?? []), ...PROFILE_FILES])]
    .filter((name) => typeof name === 'string' && /^[A-Za-z0-9._-]+$/.test(name))
  const currentProfile = new Map()
  const savedProfile = new Map()
  for (const name of profileFiles) {
    if (existsSync(join(PROFILE, name))) currentProfile.set(name, digestFile(join(PROFILE, name)))
    if (existsSync(join(LKG, 'profile', name))) savedProfile.set(name, digestFile(join(LKG, 'profile', name)))
  }
  const items = compareTrees(currentProfile, savedProfile, 'profile')
  for (const integration of manifest.integrations ?? []) {
    if (typeof integration?.target !== 'string' || !isInsideDshHome(integration.target)) continue
    if (typeof integration.snapshotName !== 'string' || !/^[A-Za-z0-9_-]+$/.test(integration.snapshotName)) continue
    const saved = join(LKG, 'integrations', integration.snapshotName)
    items.push(...compareTrees(collectTree(integration.target), collectTree(saved), `integration:${integration.id}`))
  }
  const summary = { added: 0, modified: 0, deleted: 0, unreadable: 0 }
  for (const item of items) summary[item.status] += 1
  return {
    ok: true, available: true, changed: items.length > 0,
    snapshotAt: manifest.createdAt ?? state().lastSnapshot ?? null,
    summary, items,
  }
}

function ensureSafeProfile() {
  mkdirSync(SAFE_PROFILE, { recursive: true })
  writeJsonAtomic(join(SAFE_PROFILE, 'package.json'), {
    name: 'dsh-profile-safe', private: true,
    dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'] } },
  })
  writeFileSync(join(SAFE_PROFILE, 'cordis.yml'), '[]\n')
  // Safe mode must never inherit a malformed or plugin-specific production patch.
  writeFileSync(join(SAFE_PROFILE, 'cordis.patch.yml'), '[]\n')
  const modules = join(SAFE_PROFILE, 'node_modules')
  try { if (existsSync(modules) || readlinkSync(modules)) unlinkSync(modules) } catch {}
  symlinkSync(join(PROFILE, 'node_modules'), modules, 'dir')
}

function applyRuntimePatch() {
  const patcher = join(ROOT, 'patch-client-resilience.mjs')
  if (!existsSync(patcher)) return
  const result = spawnSync(process.execPath, [patcher, resolveDshBin()], { encoding: 'utf8' })
  if (result.status !== 0) log(`runtime resilience patch skipped: ${(result.stderr || result.stdout).trim()}`)
}

async function isUp() {
  try {
    const healthPaths = state().mode === 'safe' ? []
      : guardianIntegrations().map((item) => item.healthPath).filter(Boolean)
    await health(BASE, { healthPaths, checkBundles: false })
    return true
  } catch { return false }
}

function pidFromFile() { return Number(readFileSync(PID_FILE, 'utf8').trim()) }
async function stopRunning() {
  let pid = 0
  try { pid = pidFromFile() } catch {}
  if (pid > 1) { try { process.kill(pid, 'SIGTERM') } catch {} }
  const byPort = spawnSync('lsof', ['-tiTCP:' + PORT, '-sTCP:LISTEN'], { encoding: 'utf8' }).stdout.trim().split(/\s+/)
  for (const value of byPort) {
    const found = Number(value)
    if (found > 1 && found !== pid) { try { process.kill(found, 'SIGTERM') } catch {} }
  }
  for (let n = 0; n < 30 && await isUp(); n += 1) await new Promise((accept) => setTimeout(accept, 200))
}

function spawnProfile(profileName) {
  const out = openSync(LOG_FILE, 'a')
  const child = spawn(process.execPath, [dshEntry(), '--profile', profileName, '--host', HOST, '--port', String(PORT)], {
    detached: true, env: process.env, stdio: ['ignore', out, out],
  })
  closeSync(out)
  child.unref()
  writeFileSync(PID_FILE, String(child.pid) + '\n')
  return child.pid
}

function recordFailure(message) {
  const current = state()
  const cutoff = Date.now() - 10 * 60_000
  const failures = [...(current.failures ?? []).filter((stamp) => Date.parse(stamp) > cutoff), now()]
  updateState({ failures, lastError: message })
  return failures.length
}

async function waitHealthy(profileName) {
  const deadline = Date.now() + 35_000
  let lastError = 'not ready'
  while (Date.now() < deadline) {
    try {
      const healthPaths = profileName === 'web'
        ? guardianIntegrations().map((item) => item.healthPath).filter(Boolean) : []
      return await health(BASE, { healthPaths })
    } catch (error) { lastError = String(error.message ?? error) }
    await new Promise((accept) => setTimeout(accept, 500))
  }
  throw new Error(lastError)
}

async function startSafe(reason) {
  ensureSafeProfile()
  await stopRunning()
  const pid = spawnProfile('safe')
  const result = await waitHealthy('safe')
  updateState({ mode: 'safe', pid, failures: [], lastSuccess: now(), lastError: reason })
  log(`safe mode started: ${reason}`)
  return { ok: true, mode: 'safe', pid, reason, ...result }
}

async function startProduction({ alreadyChecked = false } = {}) {
  applyRuntimePatch()
  if (!alreadyChecked) {
    const checked = await preflight()
    if (!checked.ok) {
      log(`candidate rejected before start: ${JSON.stringify(checked.issues)}`)
      if (existsSync(LKG)) {
        restoreLkg()
        const restored = await preflight()
        if (!restored.ok) return await startSafe(`candidate and LKG invalid: ${restored.issues?.join('; ')}`)
      } else return await startSafe(`candidate invalid and no LKG: ${checked.issues?.join('; ')}`)
    }
    if (checked.ok) snapshot()
  }
  await stopRunning()
  const pid = spawnProfile('web')
  try {
    const result = await waitHealthy('web')
    updateState({ mode: 'production', pid, failures: [], lastSuccess: now(), lastError: null })
    return { ok: true, mode: 'production', pid, ...result }
  } catch (error) {
    const count = recordFailure(String(error.message ?? error))
    log(`production start failed (${count}): ${error.message ?? error}`)
    await stopRunning()
    if (existsSync(LKG)) {
      restoreLkg()
      const restored = await preflight()
      if (restored.ok) {
        const retryPid = spawnProfile('web')
        try {
          const result = await waitHealthy('web')
          updateState({ mode: 'recovered', pid: retryPid, failures: [], lastSuccess: now(), lastError: null })
          return { ok: true, mode: 'recovered', pid: retryPid, ...result }
        } catch {}
      }
    }
    return await startSafe(`production failed: ${error.message ?? error}`)
  }
}

async function restartSafely() {
  const checked = await preflight()
  if (!checked.ok) return { ok: false, stopped: false, stage: checked.stage, issues: checked.issues }
  snapshot()
  return await startProduction({ alreadyChecked: true })
}

async function watchdog() {
  if (!existsSync(ENABLED_FILE)) return { ok: true, action: 'disabled' }
  if (existsSync(MAINTENANCE_FILE)) return { ok: true, action: 'maintenance' }
  if (await isUp()) return { ok: true, action: 'healthy' }
  const failures = (state().failures ?? []).filter((stamp) => Date.parse(stamp) > Date.now() - 10 * 60_000)
  if (failures.length >= 3) return await startSafe('crash-loop threshold reached')
  return { ...(await startProduction()), action: 'restarted' }
}

async function status() {
  let up = false
  let live = null
  try { live = await health(BASE, { checkBundles: false }); up = true } catch {}
  let pid = null
  if (up) {
    const found = spawnSync('lsof', ['-tiTCP:' + PORT, '-sTCP:LISTEN'], { encoding: 'utf8' }).stdout.trim()
    const parsed = Number(found.split(/\s+/)[0])
    if (parsed > 1) pid = parsed
  }
  return {
    ok: true, guardianVersion: GUARDIAN_VERSION, protocolVersion: PROTOCOL_VERSION,
    capabilities: CAPABILITIES, up, url: BASE, state: state(), lastKnownGood: existsSync(LKG),
    engine: detectEngineVersion(), pid, integrations: guardianIntegrations(), live,
  }
}

async function main() {
  if (command === 'version' || command === 'capabilities') {
    return output({ ok: true, guardianVersion: GUARDIAN_VERSION, protocolVersion: PROTOCOL_VERSION, capabilities: CAPABILITIES })
  }
  if (command === 'status') return output(await status())
  if (command === 'diff') return output(configDiff())
  if (command === 'preflight') {
    const result = await preflight({ smoke: !process.argv.includes('--quick') })
    output(result)
    if (!result.ok) process.exitCode = 1
    return
  }
  if (command === 'snapshot') return output(snapshot())
  if (command === 'disable') { rmSync(ENABLED_FILE, { force: true }); return output({ ok: true, enabled: false }) }
  if (command === 'enable') {
    writeFileSync(ENABLED_FILE, now() + '\n')
    rmSync(MAINTENANCE_FILE, { force: true })
    return output({ ok: true, enabled: true })
  }
  if (!acquireLock()) return output({ ok: false, busy: true })
  try {
    if (command === 'watchdog') return output(await watchdog())
    if (command === 'start') {
      writeFileSync(ENABLED_FILE, now() + '\n')
      rmSync(MAINTENANCE_FILE, { force: true })
      if (await isUp()) return output({ ok: true, alreadyRunning: true, ...(await status()) })
      return output(await startProduction())
    }
    if (command === 'restart') {
      writeFileSync(ENABLED_FILE, now() + '\n')
      rmSync(MAINTENANCE_FILE, { force: true })
      return output(await restartSafely())
    }
    if (command === 'recover') {
      writeFileSync(ENABLED_FILE, now() + '\n')
      rmSync(MAINTENANCE_FILE, { force: true })
      restoreLkg()
      return output(await startProduction())
    }
    if (command === 'safe-mode') {
      writeFileSync(ENABLED_FILE, now() + '\n')
      rmSync(MAINTENANCE_FILE, { force: true })
      return output(await startSafe('requested manually'))
    }
    if (command === 'stop') {
      rmSync(ENABLED_FILE, { force: true })
      writeFileSync(MAINTENANCE_FILE, now() + '\n')
      await stopRunning()
      return output({ ok: true, stopped: true })
    }
    throw new Error(`unknown command: ${command}`)
  } finally { releaseLock() }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await main() } catch (error) {
    const result = { ok: false, error: String(error?.stack ?? error) }
    output(result)
    process.exitCode = 1
  }
}

export { configDiff, copyProfileFiles, ensureSafeProfile, guardianIntegrations, restoreLkg, snapshot, validateProfileFiles }
