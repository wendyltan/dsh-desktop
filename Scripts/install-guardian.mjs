#!/usr/bin/env node
/** Install the external guardian and its user LaunchAgent with backups. */
import { spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const HOME = homedir()
const DSH_HOME = process.env.DSH_HOME ?? join(HOME, '.dsh')
const source = join(ROOT, 'Guardian')
const guardianDir = join(DSH_HOME, 'guardian')
const desktopDir = join(DSH_HOME, 'dsh-desktop')
const backupDir = join(guardianDir, 'install-backups', new Date().toISOString().replace(/[:.]/g, '-'))
const plistName = 'com.wuwendi.dsh-guardian.plist'
const plistFile = join(HOME, 'Library', 'LaunchAgents', plistName)

mkdirSync(guardianDir, { recursive: true })
mkdirSync(desktopDir, { recursive: true })
mkdirSync(dirname(plistFile), { recursive: true })
mkdirSync(backupDir, { recursive: true })

function installFile(from, to, mode) {
  if (existsSync(to)) copyFileSync(to, join(backupDir, to.split('/').at(-1)))
  const temp = `${to}.new`
  copyFileSync(from, temp)
  if (mode !== undefined) chmodSync(temp, mode)
  renameSync(temp, to)
}

installFile(join(source, 'guardian.mjs'), join(guardianDir, 'guardian.mjs'), 0o644)
installFile(join(source, 'patch-client-resilience.mjs'), join(guardianDir, 'patch-client-resilience.mjs'), 0o644)
installFile(join(source, 'README.md'), join(guardianDir, 'README.md'), 0o644)
installFile(join(ROOT, 'launch.sh'), join(desktopDir, 'launch.sh'), 0o755)
installFile(join(ROOT, 'stop.sh'), join(desktopDir, 'stop.sh'), 0o755)
installFile(join(ROOT, 'watchdog.sh'), join(desktopDir, 'watchdog.sh'), 0o755)

const plistSource = readFileSync(join(source, plistName), 'utf8')
  .replaceAll('__HOME__', HOME)
  .replaceAll('/Users/wuwendi', HOME)
if (existsSync(plistFile)) copyFileSync(plistFile, join(backupDir, plistName))
writeFileSync(`${plistFile}.new`, plistSource)
renameSync(`${plistFile}.new`, plistFile)

const lint = spawnSync('plutil', ['-lint', plistFile], { encoding: 'utf8' })
if (lint.status !== 0) throw new Error(lint.stderr || lint.stdout)
const domain = `gui/${process.getuid()}`
spawnSync('launchctl', ['bootout', domain, plistFile], { stdio: 'ignore' })
const loaded = spawnSync('launchctl', ['bootstrap', domain, plistFile], { encoding: 'utf8' })
if (loaded.status !== 0) throw new Error(loaded.stderr || loaded.stdout || 'launchctl bootstrap failed')

console.log(`guardian installed -> ${guardianDir}`)
console.log(`watchdog loaded -> ${plistFile}`)
console.log(`previous files backed up -> ${backupDir}`)
