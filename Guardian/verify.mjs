#!/usr/bin/env node
import assert from 'node:assert/strict'
import {
  appendFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync,
  symlinkSync, writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'

const root = mkdtempSync(join(tmpdir(), 'dsh-guardian-verify-'))
process.env.DSH_HOME = root

const profile = join(root, 'profiles', 'web')
const integration = join(profile, 'node_modules', 'test-integration')
const dshPackage = join(profile, 'node_modules', '@deepseek-ai', 'dsh')
mkdirSync(join(profile, 'node_modules', '.bin'), { recursive: true })
mkdirSync(join(dshPackage, 'lib'), { recursive: true })
mkdirSync(integration, { recursive: true })
writeFileSync(join(dshPackage, 'package.json'), JSON.stringify({ name: '@deepseek-ai/dsh', version: 'test' }))
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
  dsh: { guardian: {
    protocolVersion: 1,
    healthPath: '/test/status',
    snapshotLinkedBundle: true,
    profileFiles: ['.test-settings.json'],
  } },
}, null, 2))
writeFileSync(join(integration, 'marker.txt'), 'golden\n')

try {
  const guardian = await import(`./guardian.mjs?verify=${Date.now()}`)
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

  console.log('Guardian verification passed: integration, dual recovery snapshots, metadata-only diff, engine history retention, rollback/events')
} finally {
  rmSync(root, { recursive: true, force: true })
}
