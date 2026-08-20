#!/usr/bin/env node
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import {
  existsSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const sourceRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const root = mkdtempSync(join(tmpdir(), 'dsh-desktop-bridge-install-'))
const profile = join(root, 'profiles', 'web')
const guardian = join(root, 'guardian', 'guardian.mjs')
mkdirSync(join(profile, 'node_modules'), { recursive: true })
mkdirSync(dirname(guardian), { recursive: true })
writeFileSync(join(profile, 'package.json'), JSON.stringify({
  name: 'test-profile', dependencies: {},
  dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'] } },
}, null, 2) + '\n')
writeFileSync(guardian, `
const command = process.argv[2]
if (command === 'preflight' && process.env.FAIL_PREFLIGHT === '1') {
  console.log(JSON.stringify({ ok: false, stage: 'verify', issues: ['forced'] }))
  process.exit(1)
}
console.log(JSON.stringify({ ok: true, command }))
`)

function install(extra = {}) {
  return spawnSync(process.execPath, [join(sourceRoot, 'Scripts', 'install-bridge.mjs')], {
    env: { ...process.env, DSH_HOME: root, ...extra }, encoding: 'utf8',
  })
}

try {
  const first = install()
  assert.equal(first.status, 0, first.stderr || first.stdout)
  const installed = JSON.parse(readFileSync(join(profile, 'package.json'), 'utf8'))
  assert.equal(installed.dsh.profile.bundles.includes('dsh-desktop-bridge'), true)
  assert.equal(installed.dependencies['dsh-desktop-bridge'].startsWith('link:'), true)
  const live = join(profile, 'node_modules', 'dsh-desktop-bridge')
  assert.equal(existsSync(join(readlinkSync(live), 'lib', 'index.js')), true)

  const beforeFailure = readFileSync(join(profile, 'package.json'), 'utf8')
  const beforeLink = readlinkSync(live)
  const failed = install({ FAIL_PREFLIGHT: '1' })
  assert.notEqual(failed.status, 0)
  assert.equal(readFileSync(join(profile, 'package.json'), 'utf8'), beforeFailure)
  assert.equal(readlinkSync(live), beforeLink)
  console.log('Bridge installer verification passed: atomic install and Guardian-preflight rollback')
} finally {
  rmSync(root, { recursive: true, force: true })
}
