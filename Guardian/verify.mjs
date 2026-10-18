#!/usr/bin/env node
import assert from 'node:assert/strict'
import {
  appendFileSync, chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync,
  symlinkSync, utimesSync, writeFileSync,
} from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import { createServer } from 'node:net'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

async function unusedPort() {
  const probe = createServer()
  const port = await new Promise((resolve, reject) => {
    probe.once('error', reject)
    probe.listen(0, '127.0.0.1', () => resolve(probe.address().port))
  })
  await new Promise((resolve) => probe.close(resolve))
  return port
}

function verifyUpdateDowngradeGuard() {
  const home = mkdtempSync(join(tmpdir(), 'dsh-guardian-update-'))
  const profile = join(home, 'profiles', 'web')
  const modules = join(profile, 'node_modules', '@deepseek-ai')
  const current = join(modules, 'dsh')
  const sessions = join(home, 'sessions')
  const fakeBin = join(home, 'fake-bin')
  const preflightMarker = join(home, 'preflight-ran')
  const startMarker = join(home, 'start-ran')
  mkdirSync(join(current, 'lib'), { recursive: true })
  mkdirSync(join(modules, 'dsh-session', 'lib'), { recursive: true })
  mkdirSync(join(profile, 'node_modules', '.bin'), { recursive: true })
  mkdirSync(sessions, { recursive: true })
  mkdirSync(fakeBin, { recursive: true })
  writeFileSync(join(current, 'package.json'), JSON.stringify({ name: '@deepseek-ai/dsh', version: '2.0.0' }))
  writeFileSync(join(modules, 'dsh-session', 'lib', 'index.js'), 'export const SESSION_FORMAT_VERSION = 4\n')
  writeFileSync(join(current, 'lib', 'bin.js'), `#!/usr/bin/env node\nprocess.stdout.write('  - id: session-persistence-jsonl\\n    root: "${sessions}"\\n')\n`)
  symlinkSync(join(current, 'lib', 'bin.js'), join(profile, 'node_modules', '.bin', 'dsh'))
  writeFileSync(join(profile, 'package.json'), JSON.stringify({ name: 'update-guard-profile', dsh: { profile: { bundles: ['@deepseek-ai/dsh'] } } }))
  writeFileSync(join(profile, 'cordis.yml'), '[]\n')
  writeFileSync(join(profile, 'cordis.patch.yml'), '[]\n')
  writeFileSync(join(sessions, 'session.v4.jsonl'), '{}\n')
  const currentBin = join(current, 'lib', 'bin.js')
  const oldBin = join(home, 'guardian', 'engines', '1.9.0', 'dsh')
  mkdirSync(dirname(oldBin), { recursive: true })
  writeFileSync(oldBin, '')
  const selectionPath = join(home, 'guardian', 'engine.json')
  const originalSelection = JSON.stringify({
    active: currentBin, version: '2.0.0', channel: 'latest',
    history: [{ active: oldBin, version: '1.9.0', channel: 'latest' }],
  })
  writeFileSync(selectionPath, `${originalSelection}\n`)
  const npmPath = join(fakeBin, 'npm')
  writeFileSync(npmPath, `#!/usr/bin/env node
const fs = require('node:fs')
const path = require('node:path')
const prefix = process.argv[process.argv.indexOf('--prefix') + 1]
const modules = path.join(prefix, 'node_modules', '@deepseek-ai')
const pkg = path.join(modules, 'dsh')
fs.mkdirSync(path.join(pkg, 'lib'), { recursive: true })
fs.mkdirSync(path.join(modules, 'dsh-session', 'lib'), { recursive: true })
fs.mkdirSync(path.join(prefix, 'node_modules', '.bin'), { recursive: true })
fs.writeFileSync(path.join(modules, 'dsh-session', 'package.json'), JSON.stringify({ type: 'module' }))
fs.writeFileSync(path.join(pkg, 'package.json'), JSON.stringify({ name: '@deepseek-ai/dsh', version: '1.0.0' }))
fs.writeFileSync(path.join(modules, 'dsh-session', 'lib', 'index.js'), 'export const SESSION_FORMAT_VERSION = 3\\n')
fs.writeFileSync(path.join(pkg, 'lib', 'bin.js'), '#!/usr/bin/env node\\nconst fs = require("node:fs")\\nif (process.argv.includes("--dump-config")) fs.writeFileSync(process.env.DSH_TEST_PREFLIGHT_MARKER, "ran")\\nelse fs.writeFileSync(process.env.DSH_TEST_START_MARKER, "ran")\\n')
fs.chmodSync(path.join(pkg, 'lib', 'bin.js'), 0o755)
fs.symlinkSync(path.join(pkg, 'lib', 'bin.js'), path.join(prefix, 'node_modules', '.bin', 'dsh'))
`)
  chmodSync(npmPath, 0o755)
  try {
    const result = spawnSync(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), 'guardian.mjs'), 'update', '--version', '1.0.0', '--json'], {
      encoding: 'utf8', env: {
        ...process.env,
        DSH_HOME: home,
        DSH_TEST_PREFLIGHT_MARKER: preflightMarker,
        DSH_TEST_START_MARKER: startMarker,
        PATH: `${fakeBin}:${process.env.PATH}`,
      },
    })
    assert.equal(result.status, 0, result.stderr || result.stdout)
    const outcome = JSON.parse(result.stdout)
    assert.equal(outcome.ok, false)
    assert.equal(outcome.stage, 'session-compatibility')
    assert.equal(outcome.rollbackCompatibility.targetFormat, 3, JSON.stringify(outcome))
    assert.deepEqual(outcome.rollbackCompatibility.newerFormats, [4])
    assert.match(outcome.error, /Session V4/)
    assert.equal(readFileSync(selectionPath, 'utf8'), `${originalSelection}\n`)
    assert.equal(existsSync(preflightMarker), false)
    assert.equal(existsSync(startMarker), false)
    assert.deepEqual(readdirSync(join(home, 'guardian', 'engines')).filter((name) => name.startsWith('1.0.0-')), [])
    assert.equal(existsSync(oldBin), true)
    const progress = JSON.parse(readFileSync(join(home, 'guardian', 'update.json'), 'utf8'))
    assert.equal(progress.phase, 'failed')
    assert.match(progress.message, /Session V4/)
  } finally {
    rmSync(home, { recursive: true, force: true })
  }
}

const root = mkdtempSync(join(tmpdir(), 'dsh-guardian-verify-'))
process.env.DSH_HOME = root

const profile = join(root, 'profiles', 'web')
const integration = join(profile, 'node_modules', 'test-integration')
const dshPackage = join(profile, 'node_modules', '@deepseek-ai', 'dsh')
mkdirSync(join(profile, 'node_modules', '.bin'), { recursive: true })
mkdirSync(join(dshPackage, 'lib'), { recursive: true })
mkdirSync(join(dshPackage, 'node_modules', 'semver'), { recursive: true })
mkdirSync(join(profile, 'node_modules', '@deepseek-ai', 'cordis'), { recursive: true })
mkdirSync(integration, { recursive: true })
writeFileSync(join(dshPackage, 'package.json'), JSON.stringify({ name: '@deepseek-ai/dsh', version: '4.0.0-rc.1' }))
writeFileSync(join(dshPackage, 'node_modules', 'semver', 'index.js'), 'exports.validRange = (range) => typeof range === "string" && range !== "invalid" ? range : null\nexports.satisfies = (version, range, options = {}) => range === "*" ? (!version.includes("-") || options.includePrerelease === true) : range === version || range === `^${version}`\n')
writeFileSync(join(profile, 'node_modules', '@deepseek-ai', 'cordis', 'package.json'), JSON.stringify({ name: '@deepseek-ai/cordis', version: '4.0.0' }))
writeFileSync(join(dshPackage, 'lib', 'bin.js'), '#!/usr/bin/env node\n')
symlinkSync(join(dshPackage, 'lib', 'bin.js'), join(profile, 'node_modules', '.bin', 'dsh'))
writeFileSync(join(profile, 'package.json'), JSON.stringify({
  name: 'guardian-test-profile',
  dsh: { profile: { bundles: ['@deepseek-ai/dsh', 'test-integration'] } },
}, null, 2))
writeFileSync(join(profile, 'cordis.yml'), '[]\n')
writeFileSync(join(profile, 'cordis.patch.yml'), '[]\n')
writeFileSync(join(integration, 'package.json'), JSON.stringify({
  name: 'test-integration',
  peerDependencies: { '@deepseek-ai/cordis': '^4.0.2', '@deepseek-ai/dsh': '*', '@deepseek-ai/missing': '^1.0.0' },
  dsh: { bundle: true, guardian: {
    protocolVersion: 1,
    healthPath: '/test/status',
    snapshotLinkedBundle: true,
    profileFiles: ['.test-settings.json'],
  } },
}, null, 2))
const inactivePlugin = join(profile, 'node_modules', 'inactive-integration')
mkdirSync(inactivePlugin, { recursive: true })
writeFileSync(join(inactivePlugin, 'package.json'), JSON.stringify({
  name: 'inactive-integration', version: '1.0.0',
  peerDependencies: { '@deepseek-ai/cordis': '^4.0.2' }, dsh: { client: true },
}))
writeFileSync(join(integration, 'marker.txt'), 'golden\n')

try {
  verifyUpdateDowngradeGuard()
  const guardian = await import(`./guardian.mjs?verify=${Date.now()}`)
  const guardianCLI = join(dirname(fileURLToPath(import.meta.url)), 'guardian.mjs')
  const runGuardian = (action, port = 3080) => spawnSync(process.execPath, [guardianCLI, action, '--json'], {
    encoding: 'utf8', env: { ...process.env, DSH_HOME: root, DSH_WEB_PORT: String(port) },
  })
  const lock = join(root, 'guardian', '.lock')
  mkdirSync(lock)
  writeFileSync(join(lock, 'pid'), String(process.pid))
  const old = new Date(Date.now() - 360_000)
  utimesSync(lock, old, old)
  const blockedSnapshot = runGuardian('snapshot')
  assert.equal(JSON.parse(blockedSnapshot.stdout).busy, true, blockedSnapshot.stderr || blockedSnapshot.stdout)
  assert.equal(readFileSync(join(lock, 'pid'), 'utf8'), String(process.pid))
  assert.equal(existsSync(join(root, 'guardian', 'last-known-good')), false)
  rmSync(lock, { recursive: true })
  assert.equal(guardian.acquireLock(), true)
  writeFileSync(join(lock, 'owner'), 'another-owner')
  guardian.releaseLock()
  assert.equal(existsSync(lock), true)
  rmSync(lock, { recursive: true })
  mkdirSync(lock)
  utimesSync(lock, old, old)
  assert.equal(guardian.acquireLock(), true)
  guardian.releaseLock()
  assert.equal(existsSync(lock), false)
  mkdirSync(lock)
  writeFileSync(join(lock, 'pid'), '2147483647')
  mkdirSync(`${lock}.reclaim`)
  assert.equal(guardian.acquireLock(), false)
  assert.equal(readFileSync(join(lock, 'pid'), 'utf8'), '2147483647')
  rmSync(`${lock}.reclaim`, { recursive: true })
  rmSync(lock, { recursive: true })

  mkdirSync(lock)
  writeFileSync(join(lock, 'pid'), '2147483647')
  const go = join(root, 'lock-go')
  const contenderCode = `import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const guardian = await import(pathToFileURL(process.argv[2]).href);
console.log('ready');
while (!existsSync(process.argv[3])) await new Promise((resolve) => setTimeout(resolve, 5));
const acquired = guardian.acquireLock();
console.log(String(acquired));
if (acquired) await new Promise((resolve) => setTimeout(resolve, 300));
guardian.releaseLock();`
  const contenders = Array.from({ length: 3 }, () => {
    const child = spawn(process.execPath, ['--input-type=module', '-e', contenderCode, 'contender', guardianCLI, go], {
      env: { ...process.env, DSH_HOME: root }, stdio: ['ignore', 'pipe', 'pipe'],
    })
    let output = ''
    let errors = ''
    child.stdout.on('data', (chunk) => { output += chunk })
    child.stderr.on('data', (chunk) => { errors += chunk })
    return { child, ready: new Promise((resolve, reject) => {
      child.stdout.once('data', resolve)
      child.once('error', reject)
    }), done: new Promise((resolve, reject) => {
      child.once('exit', (code) => code === 0 ? resolve(() => output) : reject(new Error(errors || `contender exited ${code}`)))
      child.once('error', reject)
    }) }
  })
  await Promise.all(contenders.map((item) => item.ready))
  writeFileSync(go, '')
  const outcomes = await Promise.all(contenders.map((item) => item.done.then((read) => read().trim().split('\n').at(-1))))
  assert.deepEqual(outcomes.sort(), ['false', 'false', 'true'])

  const foreign = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' })
  try {
    await new Promise((resolve, reject) => { foreign.once('spawn', resolve); foreign.once('error', reject) })
    writeFileSync(join(root, 'logs', 'dsh-web.pid'), `${foreign.pid}\n`)
    const stopped = runGuardian('stop', await unusedPort())
    assert.equal(JSON.parse(stopped.stdout).ok, true, stopped.stderr || stopped.stdout)
    process.kill(foreign.pid, 0)
  } finally {
    foreign.kill('SIGTERM')
    rmSync(join(root, 'logs', 'dsh-web.pid'), { force: true })
  }
  const boot = { rev: 'test', entries: [{ id: 'entry', url: '/entry.js' }] }
  assert.deepEqual(guardian.bootManifest(`<head><script>window.__DSH_BOOT__ = ${JSON.stringify(boot)}<\\/script></head>`), boot)
  assert.deepEqual(guardian.bootManifest(`<head><script>globalThis["__DSH_BOOT__"] = ${JSON.stringify(boot)}<\\/script></head>`), boot)
  const accessURL = guardian.webAccessURLFromText([
    'dsh web: http://attacker.invalid/?token=wrong',
    'dsh web: http://127.0.0.1:4567/?token=smoke-secret',
  ].join('\n'), 'http://127.0.0.1:4567')
  assert.equal(accessURL?.searchParams.get('token'), 'smoke-secret')
  assert.deepEqual(
    guardian.webAccessURLsFromText([
      'dsh web: http://127.0.0.1:4567/?token=older-secret',
      'dsh web: http://127.0.0.1:4567/?token=newer-secret',
      'dsh web: http://127.0.0.1:4567/?token=older-secret',
    ].join('\n'), 'http://127.0.0.1:4567').map((item) => item.searchParams.get('token')),
    ['newer-secret', 'older-secret'],
  )
  const stderrLog = join(root, 'stderr.log')
  writeFileSync(stderrLog, 'dsh web: http://127.0.0.1:4567/?token=stderr-secret\n')
  assert.equal(
    guardian.webAccessURLFromLogs('http://127.0.0.1:4567', [
      { path: join(root, 'stdout.log'), offset: 0 },
      { path: stderrLog, offset: 0 },
    ])?.searchParams.get('token'),
    'stderr-secret',
  )
  assert.equal(
    guardian.redactWebTokens('dsh web: http://127.0.0.1:4567/?token=smoke-secret'),
    'dsh web: http://127.0.0.1:4567/?token=[redacted]',
  )
  const handoffFile = join(root, 'guardian', 'web-access-url')
  guardian.recordWebAccessURL(accessURL, 'http://127.0.0.1:4567', handoffFile)
  assert.equal(existsSync(handoffFile), true)
  assert.equal(statSync(handoffFile).mode & 0o777, 0o600)
  assert.equal(readFileSync(handoffFile, 'utf8').trim(), accessURL.href)
  assert.throws(
    () => guardian.recordWebAccessURL('http://attacker.invalid/?token=wrong', 'http://127.0.0.1:4567', handoffFile),
    /same-origin/,
  )
  guardian.recordWebAccessURL(null, 'http://127.0.0.1:4567', handoffFile)
  assert.equal(existsSync(handoffFile), false)
  const unicodeLog = join(root, 'unicode.log')
  writeFileSync(unicodeLog, '旧引擎日志\n')
  const unicodeOffset = statSync(unicodeLog).size
  appendFileSync(unicodeLog, 'dsh web: http://127.0.0.1:4567/?token=fresh-secret\n')
  assert.equal(guardian.logTextFromByteOffset(unicodeLog, unicodeOffset).startsWith('dsh web:'), true)
  assert.equal(
    guardian.webAccessURLFromLogs('http://127.0.0.1:4567', [{ path: unicodeLog, offset: unicodeOffset }])
      ?.searchParams.get('token'),
    'fresh-secret',
  )

  const originalFetch = globalThis.fetch
  const fetched = []
  globalThis.fetch = async (input, options = {}) => {
    const url = new URL(input)
    fetched.push({ url, cookie: options.headers?.cookie ?? '' })
    if (url.searchParams.get('token') === 'smoke-secret') {
      assert.equal(options.redirect, 'manual')
      return new Response(null, {
        status: 303,
        headers: {
          location: '/',
          'set-cookie': 'dsh_access=accepted; HttpOnly; SameSite=Strict',
        },
      })
    }
    assert.equal(options.headers?.cookie, 'dsh_access=accepted')
    assert.equal(url.search, '')
    if (url.pathname === '/') {
      return new Response(`<script>window.__DSH_BOOT__ = ${JSON.stringify(boot)}<\\/script>`)
    }
    if (url.pathname === '/entry.js') return new Response('window.__ModuleLoader__.load({})')
    if (url.pathname === '/test/status') {
      return new Response('{"ok":true}', { headers: { 'content-type': 'application/json' } })
    }
    return new Response('not found', { status: 404 })
  }
  try {
    const authenticated = await guardian.health('http://127.0.0.1:4567', {
      accessURL,
      healthPaths: ['/test/status'],
    })
    assert.equal(authenticated.bootRev, 'test')
    assert.deepEqual(fetched.map((item) => item.url.pathname), ['/', '/', '/entry.js', '/test/status'])
  } finally {
    globalThis.fetch = originalFetch
  }
  const integrations = guardian.guardianIntegrations()
  assert.equal(integrations.length, 1)
  assert.equal(integrations[0].id, 'test-integration')
  assert.equal(integrations[0].healthPath, '/test/status')
  assert.equal(guardian.validateProfileFiles().ok, true)
  const compatibility = guardian.pluginCompatibility(profile, join(dshPackage, 'lib', 'bin.js'))
  assert.equal(compatibility.checked, true)
  assert.equal(compatibility.issues.length, 2)
  assert.equal(compatibility.issues.find((item) => item.id === 'test-integration')?.enabled, true)
  assert.equal(compatibility.issues.find((item) => item.id === 'inactive-integration')?.enabled, false)
  assert.equal(compatibility.issues[0].issues[0].actual, '4.0.0')
  assert.equal(compatibility.issues.find((item) => item.id === 'test-integration')?.issues.some((item) => item.name === '@deepseek-ai/dsh'), false)
  assert.equal(compatibility.issues.find((item) => item.id === 'test-integration')?.issues.find((item) => item.name === '@deepseek-ai/missing')?.classification, 'unresolved')
  assert.equal(compatibility.scope, 'current')
  assert.equal(compatibility.engineVersion, '4.0.0-rc.1')
  assert.equal(typeof compatibility.checkedAt, 'string')
  assert.equal(guardian.pluginCompatibility(profile, join(dshPackage, 'lib', 'bin.js'), 'candidate').scope, 'candidate')
  const blockedPreflight = await guardian.preflight({ smoke: false, enforcePluginCompatibility: true })
  assert.equal(blockedPreflight.ok, false)
  assert.equal(blockedPreflight.stage, 'plugin-compatibility')
  assert.match(blockedPreflight.issues[0], /需要 \^4\.0\.2，当前 4\.0\.0/)
  writeFileSync(join(profile, 'package.json'), JSON.stringify({ name: 'guardian-test-profile', dsh: { profile: { bundles: ['@deepseek-ai/dsh'] } } }))
  const inactivePreflight = await guardian.preflight({ smoke: false, enforcePluginCompatibility: true })
  assert.equal(inactivePreflight.ok, true)
  assert.equal(inactivePreflight.pluginCompatibility.issues.find((item) => item.id === 'inactive-integration')?.enabled, false)
  writeFileSync(join(profile, 'package.json'), JSON.stringify({
    name: 'guardian-test-profile', dsh: { profile: { bundles: ['@deepseek-ai/dsh', 'test-integration'] } },
  }, null, 2))
  writeFileSync(join(profile, 'node_modules', '@deepseek-ai', 'cordis', 'package.json'), JSON.stringify({ name: '@deepseek-ai/cordis', version: '4.0.2' }))
  const unresolvedPreflight = await guardian.preflight({ smoke: false, enforcePluginCompatibility: true })
  assert.equal(unresolvedPreflight.ok, true)
  assert.equal(unresolvedPreflight.pluginCompatibility.issues.find((item) => item.id === 'test-integration')?.issues.find((item) => item.name === '@deepseek-ai/missing')?.classification, 'unresolved')
  writeFileSync(join(profile, 'node_modules', '@deepseek-ai', 'cordis', 'package.json'), JSON.stringify({ name: '@deepseek-ai/cordis', version: '4.0.0' }))
  writeFileSync(join(profile, 'package.json'), JSON.stringify({
    name: 'guardian-test-profile', dsh: { profile: { bundles: ['@deepseek-ai/dsh', 'test-integration'] } },
  }, null, 2))
  const sessionRoot = join(root, 'sessions')
  mkdirSync(join(sessionRoot, 'project'), { recursive: true })
  writeFileSync(join(sessionRoot, 'project', 'session.v4.jsonl'), '{}\n')
  const rollback = guardian.sessionRollbackCompatibility(join(dshPackage, 'lib', 'bin.js'), sessionRoot, {
    currentFormat: 4, targetFormat: 3,
  })
  assert.equal(rollback.safe, false)
  assert.deepEqual(rollback.newerFormats, [4])
  assert.equal(guardian.sessionRollbackCompatibility(join(dshPackage, 'lib', 'bin.js'), sessionRoot, {
    currentFormat: null, targetFormat: 3,
  }).safe, false)
  rmSync(join(sessionRoot, 'project', 'session.v4.jsonl'))
  writeFileSync(join(sessionRoot, 'project', 'session.v3.jsonl'), '{}\n')
  writeFileSync(join(sessionRoot, 'project', 'session.v2.jsonl'), '{}\n')
  assert.equal(guardian.sessionRollbackCompatibility(join(dshPackage, 'lib', 'bin.js'), sessionRoot, {
    currentFormat: 3, targetFormat: 3,
  }).safe, true)
  symlinkSync(profile, join(sessionRoot, 'linked-project'))
  assert.equal(guardian.sessionRollbackCompatibility(join(dshPackage, 'lib', 'bin.js'), sessionRoot, {
    currentFormat: 3, targetFormat: 3,
  }).safe, false)
  assert.equal(guardian.sessionRollbackCompatibility(join(dshPackage, 'lib', 'bin.js'), null, {
    currentFormat: 3, targetFormat: 3,
  }).safe, false)
  mkdirSync(join(root, 'deployments'), { recursive: true })
  const scratch = guardian.makeScratch()
  assert.equal(lstatSync(join(scratch.scratchProfile, 'node_modules')).isSymbolicLink(), false)
  assert.equal(existsSync(join(scratch.scratchProfile, 'node_modules', 'test-integration', 'marker.txt')), true)
  assert.equal(lstatSync(join(scratch.scratch, 'deployments')).isSymbolicLink(), true)
  rmSync(scratch.scratch, { recursive: true, force: true })

  guardian.snapshot()
  assert.equal(existsSync(join(root, 'guardian', 'last-known-good', 'integrations')), true)
  assert.deepEqual(guardian.configDiff().summary, { added: 0, modified: 0, deleted: 0, unreadable: 0 })

  writeFileSync(join(profile, '.test-settings.json'), '{"bad":true}\n')
  writeFileSync(join(profile, 'cordis.patch.yml'), 'not: [valid\n')
  writeFileSync(join(integration, 'marker.txt'), 'broken\n')
  const drift = guardian.configDiff()
  assert.equal(drift.changed, true)
  assert.equal(drift.items.some((item) => item.scope === 'profile' && item.path === 'cordis.patch.yml' && item.status === 'modified'), true)
  assert.equal(drift.items.some((item) => item.scope === 'profile' && item.path === '.test-settings.json' && item.status === 'added'), true)
  assert.equal(drift.items.some((item) => item.scope === 'integration:test-integration' && item.path === 'marker.txt' && item.status === 'modified'), true)
  guardian.restoreLkg()
  assert.equal(existsSync(join(profile, '.test-settings.json')), false)
  assert.equal(readFileSync(join(profile, 'cordis.patch.yml'), 'utf8'), '[]\n')
  assert.equal(readFileSync(join(integration, 'marker.txt'), 'utf8'), 'golden\n')
  assert.equal(guardian.configDiff().changed, false)
  writeFileSync(join(integration, 'marker.txt'), 'newer\n')
  guardian.snapshot()
  const snapshots = guardian.recoverySnapshots()
  assert.equal(snapshots.length, 2)
  assert.equal(snapshots[0].id, 'current')
  assert.equal(snapshots[1].id, 'previous')
  guardian.restoreLkg(join(root, 'guardian', 'last-known-good.previous'))
  assert.equal(readFileSync(join(integration, 'marker.txt'), 'utf8'), 'golden\n')

  writeFileSync(join(profile, 'cordis.patch.yml'), 'not: [valid\n')
  guardian.ensureSafeProfile()
  assert.equal(readFileSync(join(root, 'profiles', 'safe', 'cordis.patch.yml'), 'utf8'), '[]\n')

  // rollback / events（纯数据路径，不启动真实服务）
  const currentEngine = join(root, 'guardian', 'engines', '1.2.0', 'dsh')
  const previousEngine = join(root, 'guardian', 'engines', '1.1.0', 'dsh')
  mkdirSync(dirname(currentEngine), { recursive: true })
  mkdirSync(dirname(previousEngine), { recursive: true })
  writeFileSync(currentEngine, '')
  writeFileSync(previousEngine, '')
  writeFileSync(join(root, 'guardian', 'engine.json'), JSON.stringify({
    active: currentEngine, version: '1.2.0', channel: 'alpha',
    history: [{ active: previousEngine, version: '1.1.0', retainedAt: new Date().toISOString() }],
  }))
  assert.deepEqual(guardian.previousEngine(), { fromVersion: '1.2.0', toVersion: '1.1.0' })
  assert.equal(guardian.previousEngine()?.toVersion, '1.1.0')
  assert.equal(guardian.engineHistory()[0].installed, true)
  assert.equal(guardian.engineHistory()[0].channel, 'latest')
  const retention = guardian.pruneEngineEntries([
    { active: currentEngine, version: '1.2.0' },
    { active: previousEngine, version: '1.1.0' },
    { active: previousEngine, version: '1.0.0' },
  ])
  assert.equal(retention.retained.length, 2)
  assert.equal(retention.dropped[0].version, '1.0.0')
  assert.equal(guardian.successfulEngineRestore({ ok: true, mode: 'production' }, '1.1.0', '1.1.0'), true)
  assert.equal(guardian.successfulEngineRestore({ ok: true, mode: 'safe' }, '1.1.0', '1.1.0'), false)
  assert.equal(guardian.successfulEngineRestore({ ok: true, mode: 'production' }, '1.1.0', '1.2.0'), false)
  guardian.appendEvent('updated', 'engine updated', { fromVersion: '1.1.0', toVersion: '1.2.0', scope: 'engine' })
  const events = guardian.recentEvents()
  assert.equal(events.length, 1)
  assert.equal(events[0].type, 'updated')
  assert.equal(events[0].toVersion, '1.2.0')
  assert.equal(events[0].scope, 'engine')
  assert.equal(guardian.forgetEngineVersion('1.1.0').error, '当前使用 alpha 时必须保留 latest 回退版本')
  writeFileSync(join(root, 'guardian', 'engine.json'), JSON.stringify({
    active: currentEngine, version: '1.2.0', channel: 'latest',
    history: [{ active: previousEngine, version: '1.1.0', channel: 'latest', retainedAt: new Date().toISOString() }],
  }))
  assert.equal(guardian.forgetEngineVersion('1.1.0').removed, true)
  assert.equal(guardian.engineHistory().length, 0)

  const listenerScript = join(root, 'listener.cjs')
  writeFileSync(listenerScript, `const http = require('node:http')
const server = http.createServer((request, response) => {
  response.setHeader('content-type', request.url === '/test/status' ? 'application/json' : 'text/html')
  response.end(request.url === '/test/status' ? '{"ok":true}' : '<script>window.__DSH_BOOT__ = {"rev":"test","entries":[]}</script>')
})
server.listen(Number(process.argv.at(-1)), '127.0.0.1', () => process.stdout.write(String(server.address().port) + '\\n'))
`)
  const startListener = (entry, args = [], requestedPort = 0, runtime = process.execPath) => {
    const child = spawn(runtime, [entry, ...args, String(requestedPort)], {
      env: { ...process.env, DSH_HOME: root }, stdio: ['ignore', 'pipe', 'ignore'],
    })
    const port = new Promise((resolve, reject) => {
      child.stdout.once('data', (data) => resolve(Number(data.toString().trim())))
      child.once('error', reject)
      child.once('exit', (code) => reject(new Error(`listener exited: ${code}`)))
    })
    return { child, port }
  }
  const outsider = startListener(listenerScript)
  try {
    const port = await outsider.port
    const foreignStatus = runGuardian('status', port)
    const reported = JSON.parse(foreignStatus.stdout)
    assert.equal(reported.ok, false)
    assert.equal(reported.up, false, foreignStatus.stderr || foreignStatus.stdout)
    assert.equal(reported.pid, null)
    assert.equal(reported.live, null)
    assert.match(reported.error, /process ownership conflict/)
    const started = runGuardian('start', port)
    assert.equal(JSON.parse(started.stdout).ok, false, started.stderr || started.stdout)
    writeFileSync(join(root, 'guardian', 'enabled'), 'test\n')
    rmSync(join(root, 'guardian', 'maintenance'), { force: true })
    const watched = runGuardian('watchdog', port)
    assert.equal(JSON.parse(watched.stdout).ok, false, watched.stderr || watched.stdout)
    const stopped = runGuardian('stop', port)
    assert.equal(JSON.parse(stopped.stdout).ok, false, stopped.stderr || stopped.stdout)
    process.kill(outsider.child.pid, 0)
  } finally { outsider.child.kill('SIGTERM') }

  writeFileSync(currentEngine, readFileSync(listenerScript))
  writeFileSync(join(root, 'guardian', 'engine.json'), JSON.stringify({ active: currentEngine, version: '1.2.0', channel: 'latest' }))
  const alternateRuntimeDir = join(root, 'alternate-runtime')
  mkdirSync(alternateRuntimeDir)
  const alternateNode = join(alternateRuntimeDir, 'node')
  symlinkSync(process.execPath, alternateNode)
  const ownedPort = await unusedPort()
  const owned = startListener(realpathSync(currentEngine), ['--profile', 'web', '--no-open', '--host', '127.0.0.1', '--port'], ownedPort, alternateNode)
  try {
    const port = await owned.port
    writeFileSync(join(root, 'logs', 'dsh-web.pid'), `${owned.child.pid}\n`)
    const ownedStatus = JSON.parse(runGuardian('status', port).stdout)
    assert.equal(ownedStatus.ok, true)
    assert.equal(ownedStatus.up, true)
    assert.equal(ownedStatus.pid, owned.child.pid)
    const stopped = runGuardian('stop', port)
    assert.equal(JSON.parse(stopped.stdout).ok, true, stopped.stderr || stopped.stdout)
  } finally { owned.child.kill('SIGTERM') }

  console.log('Guardian verification passed: lock ownership, process ownership, integration, recovery snapshots, engine history, rollback/events')
} finally {
  rmSync(root, { recursive: true, force: true })
}
