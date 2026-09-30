#!/usr/bin/env node
import assert from 'node:assert/strict'
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { constants as zstdConstants, zstdCompressSync } from 'node:zlib'

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const testHome = join(repo, '.test-home')
process.env.DSH_HOME = testHome
const active = JSON.parse(readFileSync(join(testHome, 'guardian', 'engine.json'), 'utf8'))
const currentBin = active.active
const currentModules = dirname(dirname(dirname(currentBin)))
const enginesRoot = join(dirname(dirname(testHome)), 'guardian', 'engines')
const oldEngine = readdirSync(enginesRoot).find((name) => name.startsWith('0.1.5-rc.1-'))
assert.ok(oldEngine, 'retained dsh 0.1.5-rc.1 engine is required')
const oldBin = join(enginesRoot, oldEngine, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js')
const oldModules = dirname(dirname(dirname(oldBin)))
const guardian = await import(pathToFileURL(join(repo, 'Guardian', 'guardian.mjs')).href)
const sessionRoot = guardian.sessionPersistenceRoot(currentBin)
assert.ok(sessionRoot, 'could not determine the test session root')

const [oldSession, currentSession, oldCodecModule, catalogModule] = await Promise.all([
  import(pathToFileURL(join(oldModules, 'dsh-session', 'lib', 'index.js'))),
  import(pathToFileURL(join(currentModules, 'dsh-session', 'lib', 'index.js'))),
  import(pathToFileURL(join(oldModules, 'dsh-session-format-v2-to-v3', 'lib', 'index.js'))),
  import(pathToFileURL(join(currentModules, 'dsh-session-format-catalog', 'lib', 'index.js'))),
])
assert.equal(oldSession.SESSION_FORMAT_VERSION, 3)
assert.equal(currentSession.SESSION_FORMAT_VERSION, 4)
const catalog = catalogModule.createSessionFormatCatalogWithChildren([])
const createdAt = Date.now()
const cwd = repo
const samples = [
  { id: 'codex-visual-compat-v3', title: '内核兼容测试 · V3（勿续聊）', version: 3, createdAt },
  { id: 'codex-visual-compat-v4', title: '会话导航测试 · V4（勿续聊）', version: 4, createdAt: createdAt + 1 },
]
const projectKey = `--${cwd.replaceAll('/', '-').replace(/^-+/, '')}--`
const sampleDirs = samples.map((sample) => join(sessionRoot, projectKey, sample.id))
const sampleFiles = samples.map((sample, index) => join(sampleDirs[index], `session.v${sample.version}.jsonl.zstd`))

const eventsFor = (id, title) => [
  {
    type: 'user/message', seq: 0, time: createdAt, surfaceOp: 'append',
    data: {
      id: `${id}-message`, role: 'user', source: { kind: 'user' },
      content: [{ type: 'text', text: '仅用于桌面端兼容性、会话选择与通知导航测试。不会发起模型请求。' }],
    },
  },
  {
    type: 'session/title', seq: 1, time: createdAt + 1,
    data: { title, messageSeqs: [], source: { kind: 'user' } },
  },
]
const rowsBySample = samples.map((sample) => {
  const header = {
    version: sample.version, id: sample.id, createdAt: sample.createdAt,
    cwd, isSeeded: false, delegationDepth: 0,
  }
  const events = eventsFor(sample.id, sample.title)
  if (sample.version === 3) {
    const codec = oldCodecModule.releasedV3SessionFormatCodec
    const physicalHeader = codec.encodeHeader(header, 0)
    const physicalEvents = events.map((event) => codec.encodeEvent(event))
    const restore = catalog.createRestore(physicalHeader, { recovery: 'strict', validation: 'transformed' })
    physicalEvents.forEach((event) => restore.decodeRow(event))
    const migrated = restore.finish()
    assert.equal(migrated.header.version, 4)
    assert.equal(migrated.events.find((event) => event.type === 'session/title')?.data.title, sample.title)
    return [JSON.stringify(physicalHeader), ...physicalEvents.map(JSON.stringify)]
  }
  const physicalHeader = catalog.encodeCurrentHeader(header, 0)
  const physicalEvents = events.map((event) => catalog.encodeCurrentEvent(event))
  const restore = catalog.createRestore(physicalHeader, { recovery: 'strict', validation: 'current' })
  physicalEvents.forEach((event) => restore.decodeRow(event))
  assert.equal(restore.finish().events.find((event) => event.type === 'session/title')?.data.title, sample.title)
  return [JSON.stringify(physicalHeader), ...physicalEvents.map(JSON.stringify)]
})

const encodeFrame = (value) => zstdCompressSync(Buffer.from(value), {
  params: { [zstdConstants.ZSTD_c_checksumFlag]: 1 },
})
const encodeOfficialArtifact = (rows) => Buffer.concat([
  encodeFrame(`${rows[0]}\n`),
  ...(rows.length > 1 ? [encodeFrame(`${rows.slice(1).join('\n')}\n`)] : []),
])

// Exercise the same public storage list used by session-query, without starting a server.
const [{ Context }, { SessionQueryEngine }] = await Promise.all([
  import(pathToFileURL(join(currentModules, 'cordis', 'lib', 'index.js')).href),
  import(pathToFileURL(join(currentModules, 'dsh-session-query', 'lib', 'index.js')).href),
])
const Persistence = (await import(pathToFileURL(join(currentModules, 'dsh-session-persistence-jsonl', 'lib', 'index.js')).href)).default
const queryContext = new Context()
queryContext.sessions = { list: () => [], get: () => undefined }
const persistence = new Persistence(queryContext, { root: sessionRoot, compression: 'zstd' })
const readFixture = async (sample) => {
  const handle = await persistence.open(sample.id, 'read')
  try {
    return { header: handle.header, read: await handle.read(0) }
  } finally {
    await handle.close()
  }
}
for (let i = 0; i < samples.length; i++) {
  const sample = samples[i]
  const existingGenerations = existsSync(sampleDirs[i])
    ? readdirSync(sampleDirs[i]).filter((name) => /^session\.v\d+\.jsonl\.zstd$/.test(name))
    : []
  if (existingGenerations.length > 0) {
    const { header, read } = await readFixture(sample)
    assert.equal(header.id, sample.id, 'existing session is not the expected visual fixture; refusing to overwrite')
    assert.equal(header.cwd, cwd, 'existing session workspace differs; refusing to overwrite')
    assert.equal(read.events[0]?.type, 'user/message', 'existing fixture message differs; refusing to overwrite')
    assert.equal(read.events[0]?.data?.content?.[0]?.text, '仅用于桌面端兼容性、会话选择与通知导航测试。不会发起模型请求。', 'existing fixture message differs; refusing to overwrite')
    assert.equal(read.events[1]?.type, 'session/title', 'existing fixture title event differs; refusing to overwrite')
    assert.equal(read.events[1]?.data?.title, sample.title, 'existing fixture title differs; refusing to overwrite')
    assert.equal(read.events[1]?.data?.source?.kind, 'user', 'existing fixture title source differs; refusing to overwrite')
    if (sample.version === 3 && existingGenerations.includes('session.v3.jsonl.zstd') && existingGenerations.includes('session.v4.jsonl.zstd')) {
      const v3Header = JSON.parse(await persistence.readFirstZstdLine(sampleFiles[i]))
      assert.equal(v3Header.id, header.id, 'V3 and migrated V4 session IDs differ')
      assert.equal(v3Header.cwd, header.cwd, 'V3 and migrated V4 workspace paths differ')
      assert.equal(v3Header.createdAt, header.createdAt, 'V3 and migrated V4 session headers differ; refusing to rewrite either generation')
    }
    // Existing validated generations are strictly read-only; preserve bytes and original createdAt.
    continue
  }
  if (existsSync(sampleDirs[i]) && readdirSync(sampleDirs[i]).length > 0) {
    throw new Error(`unexpected files in visual fixture directory ${sampleDirs[i]}; refusing to overwrite`)
  }
  mkdirSync(dirname(sampleFiles[i]), { recursive: true })
  writeFileSync(sampleFiles[i], encodeOfficialArtifact(rowsBySample[i]), { flag: 'wx' })
}
const discovered = await persistence.list()
for (const sample of samples) {
  assert.ok(discovered.some(({ header }) => header.id === sample.id), `official persistence.list() did not discover ${sample.id}`)
}
for (const sample of samples) {
  const { header, read } = await readFixture(sample)
  assert.equal(header.id, sample.id)
  assert.equal(header.cwd, cwd)
  assert.ok(read.events.length >= 2)
  assert.deepEqual(read.events.slice(0, 2).map(({ type, seq }) => [type, seq]), [['user/message', 0], ['session/title', 1]])
  assert.equal(read.events[0].data.source.kind, 'user')
  assert.equal(read.events[1].data.title, sample.title)
  assert.equal(read.events[1].data.source.kind, 'user')
}
const query = new SessionQueryEngine(queryContext)
// Bind the official query corpus to this read-only fixture backend; a full Host is not needed.
query._corpus._persistence = persistence
const titleSnapshots = await query.readTitleSnapshots(samples.map(({ id }) => id))
for (let i = 0; i < samples.length; i++) {
  assert.equal(titleSnapshots[i].status, 'fulfilled')
  assert.equal(titleSnapshots[i].value.title.title, samples[i].title)
}

const pluginDir = join(testHome, 'profiles', 'web', 'node_modules', 'dsh-desktop-compatibility-fixture')
const pluginManifest = {
  name: 'dsh-desktop-compatibility-fixture',
  version: '1.0.0',
  peerDependencies: { '@deepseek-ai/dsh': '^0.1.5-rc.1' },
  dsh: { bundle: true },
}
if (existsSync(pluginDir)) {
  assert.ok(statSync(pluginDir).isDirectory(), 'compatibility fixture path must be a directory')
  assert.deepEqual(JSON.parse(readFileSync(join(pluginDir, 'package.json'), 'utf8')), pluginManifest, 'existing dependency is not the expected fixture; refusing to overwrite')
  assert.equal(readFileSync(join(pluginDir, 'patch.yml'), 'utf8'), '', 'existing fixture patch is not empty; refusing to overwrite')
} else {
  mkdirSync(pluginDir)
  writeFileSync(join(pluginDir, 'package.json'), JSON.stringify(pluginManifest, null, 2) + '\n', { flag: 'wx' })
  writeFileSync(join(pluginDir, 'patch.yml'), '', { flag: 'wx' })
}
console.log(`Official persistence list/read and session-query title snapshots verified both visual-test sessions under ${sessionRoot}; the inactive, no-code plugin fixture is ready. No model requests were sent.`)
