#!/usr/bin/env node
// A separate engine copy and empty profile: no production credentials or chats.
import { chmodSync, copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, realpathSync, readdirSync, symlinkSync, writeFileSync } from 'node:fs'
import { dirname, join, sep } from 'node:path'
import { homedir } from 'node:os'
import { fileURLToPath } from 'node:url'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const testHome = join(root, '.test-home')
const documentsDirectory = join(testHome, 'documents')
const sourceHome = process.env.DSH_SOURCE_HOME ?? join(homedir(), '.dsh')
if (process.argv.includes('--refresh')) {
  if (!existsSync(join(testHome, 'guardian', 'engine.json'))) throw new Error('请先创建测试环境。')
  for (const name of ['guardian.mjs', 'patch-client-resilience.mjs']) {
    copyFileSync(join(root, 'Guardian', name), join(testHome, 'guardian', name))
  }
  for (const name of ['launch.sh', 'stop.sh']) {
    copyFileSync(join(root, name), join(testHome, 'dsh-desktop', name))
  }
  cpSync(join(root, 'HarnessBridge'), join(testHome, 'deployments', 'dsh-desktop-bridge', 'current'), { recursive: true })
  console.log('测试组件已刷新；现有测试数据保留，运行中的服务未重启。')
  process.exit(0)
}
if (existsSync(testHome)) {
  throw new Error('测试目录已存在；保留现有数据，不自动覆盖。更新代码请使用 --refresh。')
}
const engine = JSON.parse(readFileSync(join(sourceHome, 'guardian', 'engine.json'), 'utf8'))
if (!/^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$/.test(engine.version ?? '')) throw new Error('引擎版本无效。')
const entry = realpathSync(engine.active)
const marker = '/node_modules/'
const at = entry.indexOf(marker)
if (at < 0) throw new Error('无法定位已安装引擎，未创建测试环境。')
const sourceEngine = entry.slice(0, at)
mkdirSync(testHome, { mode: 0o700 })
const testEngine = join(testHome, 'guardian', 'engines', engine.version)
cpSync(sourceEngine, testEngine, { recursive: true, verbatimSymlinks: true })
function verifyEngineLinks(directory) {
  for (const item of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, item.name)
    if (item.isSymbolicLink() && !realpathSync(path).startsWith(realpathSync(testEngine) + sep)) {
      throw new Error('引擎副本含外部链接，测试环境未启用。')
    }
    if (item.isDirectory()) verifyEngineLinks(path)
  }
}
verifyEngineLinks(testEngine)
const active = join(testEngine, entry.slice(at + 1))
writeFileSync(join(testHome, 'guardian', 'engine.json'), JSON.stringify({
  active, version: engine.version, channel: engine.channel ?? 'latest', history: [],
}) + '\n')
for (const name of ['guardian.mjs', 'patch-client-resilience.mjs']) {
  copyFileSync(join(root, 'Guardian', name), join(testHome, 'guardian', name))
}
mkdirSync(join(testHome, 'dsh-desktop'))
for (const name of ['launch.sh', 'stop.sh']) {
  const target = join(testHome, 'dsh-desktop', name)
  copyFileSync(join(root, name), target)
  chmodSync(target, 0o755)
}
const deployment = join(testHome, 'deployments', 'dsh-desktop-bridge', 'current')
cpSync(join(root, 'HarnessBridge'), deployment, { recursive: true })
const profile = join(testHome, 'profiles', 'web')
mkdirSync(join(profile, 'node_modules'), { recursive: true })
symlinkSync(deployment, join(profile, 'node_modules', 'dsh-desktop-bridge'), 'dir')
writeFileSync(join(profile, 'package.json'), JSON.stringify({
  name: 'dsh-desktop-test-profile', private: true,
  dependencies: { 'dsh-desktop-bridge': `link:${deployment}` },
  dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', 'dsh-desktop-bridge'] } },
}, null, 2) + '\n')
writeFileSync(join(profile, 'cordis.patch.yml'), [
  '- id: workspace-controller',
  '  name: "@deepseek-ai/dsh-api-workspace-controller"',
  '  config:',
  `    documentsDirectory: ${JSON.stringify(documentsDirectory)}`,
  '',
].join('\n'))
console.log(`测试环境已创建：${testHome}\n引擎：${engine.version}；端口：13080 / 13091；未复制密钥或会话。`)
