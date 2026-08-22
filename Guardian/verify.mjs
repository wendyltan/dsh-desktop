#!/usr/bin/env node
import assert from 'node:assert/strict'
import {
  existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync,
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
  const integrations = guardian.guardianIntegrations()
  assert.equal(integrations.length, 1)
  assert.equal(integrations[0].id, 'test-integration')
  assert.equal(integrations[0].healthPath, '/test/status')
  assert.equal(guardian.validateProfileFiles().ok, true)

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

  writeFileSync(join(profile, 'cordis.patch.yml'), 'not: [valid\n')
  guardian.ensureSafeProfile()
  assert.equal(readFileSync(join(root, 'profiles', 'safe', 'cordis.patch.yml'), 'utf8'), '[]\n')
  console.log('Guardian verification passed: generic integration, metadata-only diff, LKG mirror restore, safe patch isolation')
} finally {
  rmSync(root, { recursive: true, force: true })
}
