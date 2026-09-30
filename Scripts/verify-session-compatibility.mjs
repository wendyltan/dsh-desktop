#!/usr/bin/env node
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const testHome = join(repo, '.test-home')
const active = JSON.parse(readFileSync(join(testHome, 'guardian', 'engine.json'), 'utf8'))
const currentBin = active.active
const oldBin = process.env.DSH_COMPAT_OLD_DSH_BIN ?? (() => {
  const engines = join(homedir(), '.dsh', 'guardian', 'engines')
  const match = readdirSync(engines).find((name) => name.startsWith('0.1.5-rc.1-'))
  assert.ok(match, 'retained dsh 0.1.5-rc.1 engine is required')
  return join(engines, match, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js')
})()
const currentModules = dirname(dirname(dirname(currentBin)))
const oldModules = dirname(dirname(dirname(oldBin)))
const currentSession = await import(pathToFileURL(join(currentModules, 'dsh-session', 'lib', 'index.js')))
const oldSession = await import(pathToFileURL(join(oldModules, 'dsh-session', 'lib', 'index.js')))
const [formatCatalog, v3Codec, v4Codec] = await Promise.all([
  import(pathToFileURL(join(currentModules, 'dsh-session-format-catalog', 'lib', 'index.js'))),
  import(pathToFileURL(join(currentModules, 'dsh-session-format-v2-to-v3', 'lib', 'index.js'))),
  import(pathToFileURL(join(currentModules, 'dsh-session-format-v3-to-v4', 'lib', 'index.js'))),
])

assert.equal(oldSession.SESSION_FORMAT_VERSION, 3)
assert.equal(currentSession.SESSION_FORMAT_VERSION, 4)
const catalog = formatCatalog.createSessionFormatCatalogWithChildren([])
const header = {
  version: 3,
  id: 'guardian-compatibility-fixture',
  createdAt: Date.now(),
  cwd: repo,
  isSeeded: false,
  delegationDepth: 0,
}
const physicalV3 = v3Codec.releasedV3SessionFormatCodec.encodeHeader(header, 0)
const migrated = catalog.createRestore(physicalV3, { recovery: 'strict', validation: 'transformed' }).finish()
assert.equal(migrated.header.version, 4)
const physicalV4 = catalog.encodeCurrentHeader(migrated.header, migrated.inheritedEventCount)
assert.equal(v4Codec.releasedV4SessionFormatCodec.decodeHeader(physicalV4).version, 4)
assert.throws(() => v3Codec.releasedV3SessionFormatCodec.decodeHeader(physicalV4))

const scratch = mkdtempSync(join(tmpdir(), 'dsh-session-compatibility-'))
const sessions = join(scratch, 'sessions', 'test-project', 'guardian-compatibility-fixture')
const isolatedHome = join(scratch, 'home')
process.env.DSH_HOME = isolatedHome
try {
  mkdirSync(join(isolatedHome, 'profiles'), { recursive: true })
  symlinkSync(join(testHome, 'profiles', 'web'), join(isolatedHome, 'profiles', 'web'))
  const guardian = await import(pathToFileURL(join(repo, 'Guardian', 'guardian.mjs')).href)
  assert.equal(guardian.sessionPersistenceRoot(currentBin), join(isolatedHome, 'sessions'))
  const rollback = guardian.sessionRollbackCompatibility(oldBin, sessions, {
    currentFormat: currentSession.SESSION_FORMAT_VERSION,
    targetFormat: oldSession.SESSION_FORMAT_VERSION,
  })
  assert.equal(rollback.safe, true)
  mkdirSync(sessions, { recursive: true })
  writeFileSync(join(sessions, 'session.v4.jsonl'), `${JSON.stringify(physicalV4)}\n`)
  const blocked = guardian.sessionRollbackCompatibility(oldBin, join(scratch, 'sessions'), {
    currentFormat: currentSession.SESSION_FORMAT_VERSION,
    targetFormat: oldSession.SESSION_FORMAT_VERSION,
  })
  assert.equal(blocked.safe, false)
  assert.deepEqual(blocked.newerFormats, [4])
  assert.equal(guardian.sessionRollbackCompatibility(oldBin, join(scratch, 'sessions'), {
    currentFormat: null, targetFormat: oldSession.SESSION_FORMAT_VERSION,
  }).safe, false)
  const recoveryRoot = join(isolatedHome, 'sessions')
  mkdirSync(recoveryRoot, { recursive: true })
  const recoveryFile = join(recoveryRoot, 'session.v4.jsonl')
  const recoveryBytes = `${JSON.stringify(physicalV4)}\n`
  writeFileSync(recoveryFile, recoveryBytes)
  const recovery = guardian.sessionRestoreCompatibility(oldBin, currentBin)
  assert.equal(recovery.safe, false)
  assert.deepEqual(recovery.newerFormats, [4])
  assert.equal(readFileSync(recoveryFile, 'utf8'), recoveryBytes)
  rmSync(recoveryFile)
  assert.equal(guardian.sessionRestoreCompatibility(oldBin, currentBin).safe, true)
  console.log('Session compatibility verification passed: official V3→V4 migration, V3 reader refusal, rollback and failed-start recovery blocked on V4 generation')
} finally {
  rmSync(scratch, { recursive: true, force: true })
}
