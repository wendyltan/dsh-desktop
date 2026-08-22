import { copyFileSync, existsSync, readFileSync, realpathSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { spawnSync } from 'node:child_process'

const executable = process.argv[2]
if (!executable) process.exit(0)

const realExecutable = realpathSync(executable)
const marker = '/node_modules/'
const markerAt = realExecutable.lastIndexOf(marker)
if (markerAt < 0) process.exit(0)

const nodeModules = realExecutable.slice(0, markerAt + marker.length - 1)
const lib = join(nodeModules, '@deepseek-ai', 'dsh-client-modules', 'lib')
const clientFile = join(lib, 'client.js')
const serverFile = join(lib, 'index.js')
const credentialsFile = join(nodeModules, '@deepseek-ai', 'dsh-credentials-local', 'lib', 'index.js')
if (!existsSync(clientFile) || !existsSync(serverFile)) process.exit(0)

const originals = new Map([
  [clientFile, readFileSync(clientFile, 'utf8')],
  [serverFile, readFileSync(serverFile, 'utf8')],
])
if (existsSync(credentialsFile)) originals.set(credentialsFile, readFileSync(credentialsFile, 'utf8'))
let client = originals.get(clientFile)
let server = originals.get(serverFile)
let credentials = originals.get(credentialsFile)

// Repair the first rc.8-compatible patch if it was applied by an older
// version of this script. The registry stores the path under record.meta.
if (server.includes('const clientPath = record?.clientPath;')) {
  server = server.replace('const clientPath = record?.clientPath;', 'const clientPath = record?.meta?.clientPath;')
}

if (!client.includes('const loadBundleOnce =')) {
  // The rc.8 client keeps the same loader function but changed the comment
  // immediately following it. Anchor on the function and accept both known
  // layouts so an engine release cannot silently disable this patch.
  const start = client.indexOf('const defaultLoadBundle =')
  const endMarkers = [
    '\n\t\t/**\n\t\t* A plugin bundle',
    '\n\t\t/**\n\t\t* Claim and inventory',
    '\n\t/**\n\t* A plugin bundle',
    '\n/**\n* Claim and inventory',
  ]
  const end = endMarkers
    .map((marker) => client.indexOf(marker, start))
    .filter((index) => index >= 0)
    .sort((a, b) => a - b)[0] ?? -1
  if (start < 0 || end < 0) throw new Error('unsupported client loader format')
  const originalBlock = client.slice(start, end)
  const onceBlock = originalBlock.replace('const defaultLoadBundle =', 'const loadBundleOnce =')
  const retryBlock = `
\t\tconst defaultLoadBundle = async (url) => {
\t\t\tlet lastError;
\t\t\tfor (let attempt = 0; attempt < 3; attempt += 1) {
\t\t\t\tconst retryUrl = attempt === 0 ? url : \`\${url}\${url.includes("?") ? "&" : "?"}retry=\${attempt}\`;
\t\t\t\ttry {
\t\t\t\t\tawait loadBundleOnce(retryUrl);
\t\t\t\t\treturn;
\t\t\t\t} catch (error) {
\t\t\t\t\tlastError = error;
\t\t\t\t\tif (attempt < 2) await new Promise((resolve) => setTimeout(resolve, 300 * 3 ** attempt));
\t\t\t\t}
\t\t\t}
\t\t\tthrow lastError;
\t\t};`
  client = client.slice(0, start) + onceBlock + retryBlock + client.slice(end)
}

if (!server.includes('max-age=31536000, immutable')) {
  const replacements = [
    [
      'const pathname = decodeURIComponent(new URL(req.url ?? "/", "http://x").pathname);',
      'const requestUrl = new URL(req.url ?? "/", "http://x");\n\t\tconst pathname = decodeURIComponent(requestUrl.pathname);',
    ],
    [
      'const clientPath = pathname.startsWith(prefix) && pathname.endsWith(suffix) ? this.clientPath(pathname.slice(9, -suffix.length)) : void 0;',
      'const id = pathname.startsWith(prefix) && pathname.endsWith(suffix) ? pathname.slice(9, -suffix.length) : void 0;\n\t\tconst record = id === void 0 ? void 0 : this.table.get(id);\n\t\tconst clientPath = record?.clientPath;',
    ],
    [
      '"cache-control": "no-cache"',
      '"cache-control": requestUrl.searchParams.get("rev") === record?.entry.rev ? "public, max-age=31536000, immutable" : "no-cache"',
    ],
  ]
  for (const [before, after] of replacements) {
    if (!server.includes(before)) throw new Error(`unsupported bundle server format near: ${before}`)
    server = server.replace(before, after)
  }
}

// Older DSH clients persist credentials as `{ version, refs }`, while the
// newer credentials provider expects a flat map. Read both shapes so a
// Guardian restart never requires rewriting the user's secrets file.
if (credentials && !credentials.includes('const legacyRefs = root.refs;')) {
  const before = `const root = document.toJS() ?? {};
	if (typeof root !== "object" || root === null || Array.isArray(root)) throw new TypeError(\`credentials-local: \${filename} must be a mapping of credential reference to value\`);
	const entries = /* @__PURE__ */ new Map();
	for (const [key, value] of Object.entries(root)) {`
  const after = `const root = document.toJS() ?? {};
	if (typeof root !== "object" || root === null || Array.isArray(root)) throw new TypeError(\`credentials-local: \${filename} must be a mapping of credential reference to value\`);
	const legacyRefs = root.refs;
	const values = typeof legacyRefs === "object" && legacyRefs !== null && !Array.isArray(legacyRefs) ? legacyRefs : root;
	const entries = /* @__PURE__ */ new Map();
	for (const [key, value] of Object.entries(values)) {`
  if (credentials.includes(before)) credentials = credentials.replace(before, after)
}

if (client === originals.get(clientFile) && server === originals.get(serverFile) && credentials === originals.get(credentialsFile)) process.exit(0)

for (const [file, original] of originals) {
  const backup = `${file}.pre-resilience.bak`
  if (!existsSync(backup)) writeFileSync(backup, original)
}

try {
  writeFileSync(clientFile, client)
  writeFileSync(serverFile, server)
  if (credentials !== undefined) writeFileSync(credentialsFile, credentials)
  for (const file of [clientFile, serverFile, credentialsFile].filter(existsSync)) {
    const checked = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' })
    if (checked.status !== 0) throw new Error(`${file}: ${checked.stderr}`)
  }
  console.log(`[dsh] applied client resilience patch to ${dirname(lib)}`)
} catch (error) {
  for (const [file, original] of originals) writeFileSync(file, original)
  throw error
}
