#!/usr/bin/env node
/** Explicit, atomic deployment of the desktop-owned Harness adapter.
 * This script is intentionally not called by build.sh because it mutates the
 * live web profile and approval chain. Guardian preflight gates the change. */
import { spawnSync } from 'node:child_process'
import {
  chmodSync, cpSync, existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync,
  readdirSync, renameSync, rmSync, symlinkSync, writeFileSync,
} from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const SOURCE = join(ROOT, 'HarnessBridge')
const DSH_HOME = process.env.DSH_HOME ?? join(homedir(), '.dsh')
const PROFILE = join(DSH_HOME, 'profiles', 'web')
const DEPLOY_ROOT = join(DSH_HOME, 'deployments', 'dsh-desktop-bridge')
const CURRENT = join(DEPLOY_ROOT, 'current')
const BACKUPS = join(DEPLOY_ROOT, 'backups')
const LIVE_LINK = join(PROFILE, 'node_modules', 'dsh-desktop-bridge')
const PROFILE_PACKAGE = join(PROFILE, 'package.json')
const GUARDIAN = join(DSH_HOME, 'guardian', 'guardian.mjs')
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
const originalProfile = readFileSync(PROFILE_PACKAGE, 'utf8')
let originalLink = null

if (!existsSync(GUARDIAN)) throw new Error(`guardian missing: ${GUARDIAN}`)
try {
  if (!lstatSync(LIVE_LINK).isSymbolicLink()) throw new Error(`refusing to replace non-symlink: ${LIVE_LINK}`)
  originalLink = readlinkSync(LIVE_LINK)
} catch (error) {
  if (existsSync(LIVE_LINK)) throw error
}

const checked = spawnSync(process.execPath, ['--check', join(SOURCE, 'lib', 'index.js')], { encoding: 'utf8' })
if (checked.status !== 0) throw new Error(checked.stderr || checked.stdout || 'bridge syntax check failed')
const pkg = JSON.parse(readFileSync(join(SOURCE, 'package.json'), 'utf8'))
if (pkg.name !== 'dsh-desktop-bridge' || pkg.dsh?.guardian?.protocolVersion !== 1) {
  throw new Error('invalid bridge package metadata')
}

mkdirSync(BACKUPS, { recursive: true })
const candidate = join(DEPLOY_ROOT, `.candidate-${stamp}`)
rmSync(candidate, { recursive: true, force: true })
mkdirSync(candidate, { recursive: true })
for (const item of ['package.json', 'cordis.patch.yml', 'lib']) cpSync(join(SOURCE, item), join(candidate, item), { recursive: true })

let backup = null
if (existsSync(CURRENT)) {
  backup = join(BACKUPS, stamp)
  renameSync(CURRENT, backup)
}
renameSync(candidate, CURRENT)

function restore(reason) {
  const failed = join(DEPLOY_ROOT, `failed-${stamp}`)
  if (existsSync(CURRENT)) renameSync(CURRENT, failed)
  if (backup !== null) renameSync(backup, CURRENT)
  writeFileSync(PROFILE_PACKAGE, originalProfile)
  rmSync(LIVE_LINK, { recursive: true, force: true })
  if (originalLink !== null) symlinkSync(originalLink, LIVE_LINK, 'dir')
  throw new Error(`${reason}; desktop bridge deployment rolled back`)
}

try {
  const profile = JSON.parse(originalProfile)
  profile.dependencies ??= {}
  profile.dependencies['dsh-desktop-bridge'] = `link:${CURRENT}`
  profile.dsh ??= {}
  profile.dsh.profile ??= {}
  profile.dsh.profile.bundles ??= []
  if (!profile.dsh.profile.bundles.includes('dsh-desktop-bridge')) {
    profile.dsh.profile.bundles.push('dsh-desktop-bridge')
  }
  writeFileSync(`${PROFILE_PACKAGE}.new`, JSON.stringify(profile, null, 2) + '\n')
  renameSync(`${PROFILE_PACKAGE}.new`, PROFILE_PACKAGE)

  const tempLink = `${LIVE_LINK}.new`
  rmSync(tempLink, { recursive: true, force: true })
  symlinkSync(CURRENT, tempLink, 'dir')
  rmSync(LIVE_LINK, { recursive: true, force: true })
  renameSync(tempLink, LIVE_LINK)

  const preflight = spawnSync(process.execPath, [GUARDIAN, 'preflight', '--json'], { encoding: 'utf8', timeout: 120_000 })
  process.stdout.write(preflight.stdout || '')
  let ok = preflight.status === 0
  try { ok &&= JSON.parse(preflight.stdout).ok === true } catch { ok = false }
  if (!ok) restore('Guardian preflight failed')
} catch (error) {
  if (String(error?.message ?? error).includes('deployment rolled back')) throw error
  restore(String(error?.message ?? error))
}

function makeReadOnly(path) {
  const info = lstatSync(path)
  if (info.isDirectory()) for (const name of readdirSync(path)) makeReadOnly(join(path, name))
  else if (info.isFile()) chmodSync(path, 0o444)
}
makeReadOnly(CURRENT)
spawnSync(process.execPath, [GUARDIAN, 'snapshot', '--json'], { stdio: 'inherit' })

const names = readdirSync(BACKUPS).filter((name) => /^\d{4}-\d{2}-\d{2}T/.test(name)).sort()
while (names.length > 8) rmSync(join(BACKUPS, names.shift()), { recursive: true, force: true })
console.log(`desktop bridge deployed safely -> ${CURRENT}`)
