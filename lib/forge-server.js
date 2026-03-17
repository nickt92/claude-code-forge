#!/usr/bin/env node
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// forge-server — local web management interface for forge
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Zero-dependency Node.js HTTP server. Binds to 127.0.0.1 only.
// All forge logic remains in bash — this is a thin REST wrapper.
//
// Security model:
//   - Binds 127.0.0.1 only (no remote access)
//   - Random session token required on POST/DELETE via X-Forge-Token header
//   - execFile with array args (never shell string interpolation)
//   - Path traversal validation on name/path parameters
//   - Content-Type check on POST (rejects form-urlencoded)

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFile } = require('child_process');
const os = require('os');

// ── Configuration ─────────────────────────────────────────────

const CLAUDE_DIR = path.join(os.homedir(), '.claude');
const FORGE_SOURCE_DIR = path.resolve(__dirname, '..');
const PROFILES_DIR = path.join(FORGE_SOURCE_DIR, 'templates', 'profiles');
const SECTIONS_DIR = path.join(FORGE_SOURCE_DIR, 'templates', 'sections');
const USER_PROFILES_DIR = path.join(CLAUDE_DIR, 'profiles');
const PLUGIN_GROUPS_FILE = path.join(FORGE_SOURCE_DIR, 'templates', 'plugin-groups.json');
const MANIFEST_FILE = path.join(CLAUDE_DIR, 'forge-backup', 'manifest.json');
const CONFIG_FILE = path.join(CLAUDE_DIR, 'forge-config.json');
const SECURITY_LOG = path.join(CLAUDE_DIR, 'security.log');
const WEB_DIR = path.join(FORGE_SOURCE_DIR, 'web');

const PID_FILE = path.join(CLAUDE_DIR, 'forge-ui.pid');
const PORT_FILE = path.join(CLAUDE_DIR, 'forge-ui.port');
const TOKEN_FILE = path.join(CLAUDE_DIR, 'forge-ui.token');

const SESSION_TOKEN = crypto.randomBytes(32).toString('hex');
const START_TIME = Date.now();

// ── Helpers ───────────────────────────────────────────────────

function ok(data) {
  return JSON.stringify({ ok: true, data, error: null });
}

function err(message, statusCode) {
  return { body: JSON.stringify({ ok: false, data: null, error: message }), statusCode: statusCode || 500 };
}

function readJsonFile(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function writeJsonFileAtomic(filePath, data) {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const tmp = filePath + '.tmp.' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', 'utf8');
  fs.renameSync(tmp, filePath);
}

function safePersonaName(name) {
  return /^[a-zA-Z][a-zA-Z0-9-]*$/.test(name);
}

function isBuiltinPersona(name) {
  return fs.existsSync(path.join(PROFILES_DIR, name + '.json')) && !name.startsWith('custom-');
}

function findProfileFile(name) {
  const builtin = path.join(PROFILES_DIR, name + '.json');
  if (fs.existsSync(builtin)) return builtin;
  const custom = path.join(USER_PROFILES_DIR, name + '.json');
  if (fs.existsSync(custom)) return custom;
  return null;
}

function resolvedPathWithin(name, baseDir) {
  const resolved = path.resolve(baseDir, name);
  return resolved.startsWith(path.resolve(baseDir) + path.sep) || resolved === path.resolve(baseDir);
}

function stripAnsi(str) {
  return str.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, '');
}

function runForgeCommand(args, timeout, opts) {
  return new Promise((resolve, reject) => {
    const forgePath = path.join(FORGE_SOURCE_DIR, 'forge');
    const execOpts = {
      timeout: timeout || 30000,
      env: { ...process.env, NO_COLOR: '1', UI_QUIET: 'false' },
      maxBuffer: 1024 * 1024,
    };
    if (opts && opts.cwd) execOpts.cwd = opts.cwd;
    execFile(forgePath, args, execOpts, (error, stdout, stderr) => {
      if (error && error.killed) {
        reject(new Error('Command timed out'));
      } else {
        resolve({ stdout: stripAnsi(stdout || ''), stderr: stripAnsi(stderr || ''), code: error ? error.code || 1 : 0 });
      }
    });
  });
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let done = false;
    const fail = (e) => { if (!done) { done = true; reject(e); } };
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 1024 * 64) {
        req.destroy();
        fail(new Error('Body too large'));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (done) return;
      try {
        const raw = Buffer.concat(chunks).toString('utf8');
        done = true;
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        fail(new Error('Invalid JSON'));
      }
    });
    req.on('error', (e) => fail(e));
  });
}

function getForgeVersion() {
  try {
    const manifest = path.join(FORGE_SOURCE_DIR, 'lib', 'manifest.sh');
    const content = fs.readFileSync(manifest, 'utf8');
    const match = content.match(/FORGE_VERSION="\$\{FORGE_VERSION:-([^}]+)\}"/);
    if (match) return match[1];
    const match2 = content.match(/FORGE_VERSION="([^"]+)"/);
    return match2 ? match2[1] : 'unknown';
  } catch {
    return 'unknown';
  }
}

// ── Route Handlers (GET) ──────────────────────────────────────

function handleGetHealth() {
  const available = getForgeVersion();
  const manifest = readJsonFile(MANIFEST_FILE);
  const installed = manifest ? manifest.forge_version : available;
  return ok({
    uptime: Math.floor((Date.now() - START_TIME) / 1000),
    forge_version: available,
    installed_version: installed,
    update_available: installed !== available,
    node_version: process.version,
    pid: process.pid,
  });
}

function handleGetStatus() {
  const profile = readJsonFile(path.join(CLAUDE_DIR, 'profile.json'));
  const manifest = readJsonFile(MANIFEST_FILE);
  const config = readJsonFile(CONFIG_FILE) || {};
  const settings = readJsonFile(path.join(CLAUDE_DIR, 'settings.json'));

  const hookCount = settings && settings.hooks
    ? Object.values(settings.hooks).reduce((n, arr) => n + (Array.isArray(arr) ? arr.length : 0), 0)
    : 0;
  const pluginCount = settings && settings.enabledPlugins
    ? Object.values(settings.enabledPlugins).filter(Boolean).length
    : 0;

  let rulesCount = 0;
  const rulesDir = path.join(CLAUDE_DIR, 'rules');
  try {
    rulesCount = fs.readdirSync(rulesDir).filter(f => f.endsWith('.md')).length;
  } catch {}

  return ok({
    persona: profile || null,
    manifest: manifest ? {
      forge_version: manifest.forge_version,
      install_timestamp: manifest.install_timestamp,
      plugin_group: manifest.plugin_group,
      manifest_version: manifest.manifest_version,
    } : null,
    hooks: hookCount,
    plugins: pluginCount,
    rules: rulesCount,
    config,
  });
}

function handleGetPersonas() {
  const personas = [];

  // Built-in
  try {
    for (const f of fs.readdirSync(PROFILES_DIR)) {
      if (!f.endsWith('.json')) continue;
      const data = readJsonFile(path.join(PROFILES_DIR, f));
      if (data) personas.push({ ...data, source: 'builtin' });
    }
  } catch {}

  // Custom (user-space)
  try {
    for (const f of fs.readdirSync(USER_PROFILES_DIR)) {
      if (!f.endsWith('.json')) continue;
      const data = readJsonFile(path.join(USER_PROFILES_DIR, f));
      if (data) personas.push({ ...data, source: 'custom' });
    }
  } catch {}

  // Sort: current first, then alphabetical
  const currentProfile = readJsonFile(path.join(CLAUDE_DIR, 'profile.json'));
  const currentPersona = currentProfile ? currentProfile.persona : '';
  personas.sort((a, b) => {
    if (a.persona === currentPersona) return -1;
    if (b.persona === currentPersona) return 1;
    return (a.label || a.persona).localeCompare(b.label || b.persona);
  });

  return ok({ personas, current: currentPersona });
}

function handleGetPersonaDetail(name) {
  if (!safePersonaName(name) && !(name.startsWith('custom-') && safePersonaName(name.slice(7)))) {
    return err('Invalid persona name', 400);
  }
  const file = findProfileFile(name);
  if (!file) return err('Persona not found', 404);
  const data = readJsonFile(file);
  if (!data) return err('Failed to read persona', 500);
  return ok({ ...data, source: file.includes(USER_PROFILES_DIR) ? 'custom' : 'builtin' });
}

function handleGetConfig() {
  return ok(readJsonFile(CONFIG_FILE) || {});
}

function handleGetPlugins() {
  const groups = readJsonFile(PLUGIN_GROUPS_FILE) || {};
  const settings = readJsonFile(path.join(CLAUDE_DIR, 'settings.json'));
  const installed = settings && settings.enabledPlugins
    ? Object.entries(settings.enabledPlugins).filter(([, v]) => v).map(([k]) => k)
    : [];
  const manifest = readJsonFile(MANIFEST_FILE);
  const currentGroup = manifest ? manifest.plugin_group || 'full' : 'unknown';
  return ok({ groups, installed, current_group: currentGroup });
}

function parseSecurityLine(line) {
  // Format: 2026-03-16T06:57:26Z TYPE tool=X key="value" ...
  const m = line.match(/^(\d{4}-\d{2}-\d{2}T[\d:]+Z)\s+(\S+)\s*(.*)/);
  if (!m) return { raw: line };
  const entry = { timestamp: m[1], type: m[2], raw: line };
  // Parse key=value pairs from the rest
  const rest = m[3];
  const toolMatch = rest.match(/tool=(\S+)/);
  if (toolMatch) entry.tool = toolMatch[1];
  const typesMatch = rest.match(/types="([^"]+)"/);
  if (typesMatch) entry.detail = typesMatch[1];
  // Parse command if present
  const cmdMatch = rest.match(/command="([^"]+)"/);
  if (cmdMatch) entry.command = cmdMatch[1];
  const reasonMatch = rest.match(/reason="([^"]+)"/);
  if (reasonMatch) entry.reason = reasonMatch[1];
  return entry;
}

function handleGetSecurity() {
  const entries = [];
  try {
    const content = fs.readFileSync(SECURITY_LOG, 'utf8');
    const lines = content.trim().split('\n').filter(Boolean);
    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const parsed = JSON.parse(lines[i]);
        entries.push(parsed);
      } catch {
        entries.push(parseSecurityLine(lines[i]));
      }
    }
  } catch {}
  return ok({ entries, count: entries.length });
}

function handleGetSessions() {
  const backupDir = path.join(CLAUDE_DIR, 'forge-backup');
  const sessions = [];
  try {
    for (const f of fs.readdirSync(backupDir)) {
      if (!f.endsWith('.json') || f === 'manifest.json') continue;
      const stat = fs.statSync(path.join(backupDir, f));
      sessions.push({
        name: f,
        size: stat.size,
        modified: stat.mtime.toISOString(),
      });
    }
  } catch {}
  sessions.sort((a, b) => new Date(b.modified) - new Date(a.modified));
  return ok({ sessions, count: sessions.length });
}

function handleGetAxes() {
  const axes = { communication: [], autonomy: [], workflow: [], depth: [] };
  try {
    for (const f of fs.readdirSync(SECTIONS_DIR)) {
      if (!f.endsWith('.md')) continue;
      for (const axis of Object.keys(axes)) {
        if (f.startsWith(axis + '-')) {
          const value = f.slice(axis.length + 1, -3); // remove axis- prefix and .md suffix
          axes[axis].push(value);
        }
      }
    }
  } catch {}
  // Sort each axis
  for (const k of Object.keys(axes)) axes[k].sort();
  return ok(axes);
}

async function handleGetDashboard() {
  try {
    const result = await runForgeCommand(['dashboard', '--json'], 120000);
    const data = JSON.parse(result.stdout.trim());
    return ok(data);
  } catch (e) {
    return err('Dashboard collection failed: ' + e.message, 500);
  }
}

// ── Route Handlers (POST) ─────────────────────────────────────

async function handlePostSwitch(body) {
  const persona = body.persona;
  if (!persona || typeof persona !== 'string') return err('Missing persona field', 400);
  if (!safePersonaName(persona) && !persona.startsWith('custom-')) return err('Invalid persona name', 400);
  if (!findProfileFile(persona)) return err('Persona not found: ' + persona, 404);

  try {
    const result = await runForgeCommand(['switch', persona]);
    if (result.code !== 0) return err('Switch failed: ' + (result.stderr || result.stdout), 500);
    return ok({ persona, output: result.stdout.trim() });
  } catch (e) {
    return err('Switch failed: ' + e.message, 500);
  }
}

async function handlePostConfig(body) {
  const { key, value } = body;
  if (!key || typeof key !== 'string') return err('Missing key field', 400);
  if (value === undefined || value === null) return err('Missing value field', 400);
  if (!/^[a-zA-Z0-9_.]+$/.test(key)) return err('Invalid key (alphanumeric, dots, underscores only)', 400);

  try {
    const result = await runForgeCommand(['config', 'set', key, String(value)]);
    if (result.code !== 0) return err('Config set failed: ' + (result.stderr || result.stdout), 500);
    return ok({ key, value, output: result.stdout.trim() });
  } catch (e) {
    return err('Config set failed: ' + e.message, 500);
  }
}

async function handlePostBuild(body) {
  const { name, communication, autonomy, workflow, depth, quality, default_plugin_group } = body;

  // Validate all fields
  if (!name || typeof name !== 'string') return err('Missing name', 400);
  if (!/^[a-zA-Z][a-zA-Z0-9-]*$/.test(name)) return err('Invalid name (letters, numbers, hyphens, must start with letter)', 400);
  if (fs.existsSync(path.join(PROFILES_DIR, name + '.json'))) return err('A built-in persona with that name already exists', 409);

  const validComm = ['plain', 'technical', 'expert'];
  const validAuto = ['guided', 'moderate', 'high'];
  const validWork = ['simplified', 'standard', 'advanced'];
  const validDepth = ['conceptual', 'practical', 'engineering'];
  const validPlugins = ['full', 'standard', 'minimal'];
  const validQuality = ['core', 'engineering'];

  if (!validComm.includes(communication)) return err('Invalid communication: ' + communication, 400);
  if (!validAuto.includes(autonomy)) return err('Invalid autonomy: ' + autonomy, 400);
  if (!validWork.includes(workflow)) return err('Invalid workflow: ' + workflow, 400);
  if (!validDepth.includes(depth)) return err('Invalid depth: ' + depth, 400);
  if (default_plugin_group && !validPlugins.includes(default_plugin_group)) return err('Invalid plugin group', 400);
  if (quality && !Array.isArray(quality)) return err('Quality must be an array', 400);
  if (quality) {
    for (const q of quality) {
      if (!validQuality.includes(q)) return err('Invalid quality value: ' + q, 400);
    }
  }

  // Validate sections exist
  const sectionChecks = [
    `communication-${communication}.md`,
    `autonomy-${autonomy}.md`,
    `workflow-${workflow}.md`,
    `depth-${depth}.md`,
  ];
  for (const s of sectionChecks) {
    if (!fs.existsSync(path.join(SECTIONS_DIR, s))) return err('Missing section: ' + s, 500);
  }

  const personaKey = 'custom-' + name;
  const displayName = name.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  const profile = {
    schema_version: 1,
    persona: personaKey,
    label: displayName + ' (Custom)',
    description: 'Custom persona built via forge ui',
    axes: { communication, autonomy, workflow, depth },
    quality: quality || ['core'],
    default_plugin_group: default_plugin_group || 'full',
  };

  // Atomic write
  const profileDir = USER_PROFILES_DIR;
  if (!fs.existsSync(profileDir)) fs.mkdirSync(profileDir, { recursive: true });
  writeJsonFileAtomic(path.join(profileDir, personaKey + '.json'), profile);

  return ok({ persona: personaKey, profile });
}

async function handlePostInstall(body) {
  const args = ['install'];
  if (body.profile) {
    if (!safePersonaName(body.profile) && !body.profile.startsWith('custom-')) return err('Invalid profile name', 400);
    args.push('--profile', body.profile);
  } else {
    // Auto-detect current persona to skip interactive prompt
    const profile = readJsonFile(path.join(CLAUDE_DIR, 'profile.json'));
    if (profile && profile.persona) {
      args.push('--profile', profile.persona);
    }
  }
  if (body.plugins) {
    if (!['full', 'standard', 'minimal'].includes(body.plugins)) return err('Invalid plugin group', 400);
    args.push('--plugins', body.plugins);
  }
  args.push('--quiet');

  try {
    const result = await runForgeCommand(args, 120000);
    if (result.code !== 0) return err('Install failed: ' + (result.stderr || result.stdout), 500);
    return ok({ output: result.stdout.trim() });
  } catch (e) {
    return err('Install failed: ' + e.message, 500);
  }
}

async function handlePostInit(body) {
  const targetPath = body.path;
  if (!targetPath || typeof targetPath !== 'string') return err('Missing path field', 400);
  const resolved = path.resolve(targetPath);
  try {
    const stat = fs.statSync(resolved);
    if (!stat.isDirectory()) return err('Path is not a directory', 400);
  } catch {
    return err('Path does not exist', 400);
  }
  // Validate path doesn't escape home
  const home = process.env.HOME || process.env.USERPROFILE || '/';
  if (!resolved.startsWith(home)) return err('Path must be within home directory', 400);

  const args = ['init'];
  if (body.docs) args.push('--docs');
  if (body.persona) {
    if (!safePersonaName(body.persona) && !body.persona.startsWith('custom-')) return err('Invalid persona name', 400);
    args.push('--persona', body.persona);
  }
  if (body.skip_docs) args.push('--skip-docs');

  try {
    const result = await runForgeCommand(args, 30000, { cwd: resolved });
    return ok({ output: result.stdout.trim(), code: result.code, path: resolved });
  } catch (e) {
    return err('Init failed: ' + e.message, 500);
  }
}

async function handlePostDoctor() {
  try {
    const result = await runForgeCommand(['doctor'], 30000);
    return ok({ output: result.stdout.trim(), code: result.code });
  } catch (e) {
    return err('Doctor failed: ' + e.message, 500);
  }
}

async function handlePostDiff() {
  try {
    const result = await runForgeCommand(['diff'], 30000);
    return ok({ output: result.stdout.trim(), code: result.code });
  } catch (e) {
    return err('Diff failed: ' + e.message, 500);
  }
}

async function handlePostDashboardScan(body) {
  const scanPath = body.path;
  const scanDepth = body.depth || 3;
  if (!scanPath || typeof scanPath !== 'string') return err('Missing path field', 400);
  if (typeof scanDepth !== 'number' || scanDepth < 1 || scanDepth > 10) return err('Depth must be 1-10', 400);

  // Validate path exists, is a directory, and is within home
  const resolved = path.resolve(scanPath);
  const home = process.env.HOME || process.env.USERPROFILE || '/';
  if (!resolved.startsWith(home)) return err('Path must be within home directory', 400);
  try {
    const stat = fs.statSync(resolved);
    if (!stat.isDirectory()) return err('Path is not a directory', 400);
  } catch {
    return err('Path does not exist', 400);
  }

  // Set config then run dashboard --json for structured data
  try {
    await runForgeCommand(['config', 'set', 'dashboard.scan_path', resolved]);
    await runForgeCommand(['config', 'set', 'dashboard.scan_depth', String(scanDepth)]);
    const result = await runForgeCommand(['dashboard', '--json'], 120000);
    const data = JSON.parse(result.stdout.trim());
    return ok(data);
  } catch (e) {
    return err('Scan failed: ' + e.message, 500);
  }
}

function handleDeletePersona(name) {
  if (!safePersonaName(name) && !name.startsWith('custom-')) return err('Invalid persona name', 400);

  // Reject deletion of built-in personas
  if (isBuiltinPersona(name)) return err('Cannot delete built-in persona: ' + name, 403);

  // Must be a custom persona
  const file = path.join(USER_PROFILES_DIR, name + '.json');
  if (!fs.existsSync(file)) {
    // Also check source profiles dir for custom- prefixed
    const srcFile = path.join(PROFILES_DIR, name + '.json');
    if (fs.existsSync(srcFile) && name.startsWith('custom-')) {
      return err('Cannot delete source-bundled persona. Remove manually from templates/profiles/', 403);
    }
    return err('Persona not found', 404);
  }

  // Path traversal check
  const resolved = path.resolve(file);
  if (!resolved.startsWith(path.resolve(USER_PROFILES_DIR))) {
    return err('Path traversal rejected', 400);
  }

  // Check if this is the active persona
  const currentProfile = readJsonFile(path.join(CLAUDE_DIR, 'profile.json'));
  if (currentProfile && currentProfile.persona === name) {
    return err('Cannot delete the currently active persona. Switch first.', 409);
  }

  fs.unlinkSync(file);
  return ok({ deleted: name });
}

// ── Router ────────────────────────────────────────────────────

async function handleRequest(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  const pathname = url.pathname;
  const method = req.method;

  // CORS for local dev (not strictly needed for same-origin, but safe)
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Cache-Control', 'no-store');

  // Serve SPA
  if (method === 'GET' && (pathname === '/' || pathname === '/index.html')) {
    // Accept token via query param on initial page load
    const queryToken = url.searchParams.get('token');
    try {
      let html = fs.readFileSync(path.join(WEB_DIR, 'index.html'), 'utf8');
      // Inject token into page so JS can read it
      const safeToken = (queryToken && /^[a-f0-9]{64}$/.test(queryToken)) ? queryToken : '';
      html = html.replace('__FORGE_TOKEN__', safeToken);
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    } catch {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('Failed to load UI');
    }
    return;
  }

  // API routes
  if (pathname.startsWith('/api/')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');

    // Token check for mutations
    if (method === 'POST' || method === 'DELETE') {
      const token = req.headers['x-forge-token'] || '';
      const tokenBuf = Buffer.from(token, 'utf8');
      const expectedBuf = Buffer.from(SESSION_TOKEN, 'utf8');
      if (tokenBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(tokenBuf, expectedBuf)) {
        const e = err('Invalid or missing session token', 403);
        res.writeHead(e.statusCode);
        res.end(e.body);
        return;
      }

      // Content-Type check for POST
      if (method === 'POST') {
        const ct = (req.headers['content-type'] || '').toLowerCase();
        if (ct.includes('application/x-www-form-urlencoded')) {
          const e = err('Form-urlencoded not accepted', 415);
          res.writeHead(e.statusCode);
          res.end(e.body);
          return;
        }
      }
    }

    let result;
    try {
      // GET routes
      if (method === 'GET') {
        if (pathname === '/api/health') result = handleGetHealth();
        else if (pathname === '/api/status') result = handleGetStatus();
        else if (pathname === '/api/personas') result = handleGetPersonas();
        else if (pathname === '/api/config') result = handleGetConfig();
        else if (pathname === '/api/plugins') result = handleGetPlugins();
        else if (pathname === '/api/security') result = handleGetSecurity();
        else if (pathname === '/api/sessions') result = handleGetSessions();
        else if (pathname === '/api/axes') result = handleGetAxes();
        else if (pathname === '/api/dashboard') result = await handleGetDashboard();
        else if (pathname.match(/^\/api\/personas\/[^/]+$/)) {
          const name = decodeURIComponent(pathname.split('/').pop());
          result = handleGetPersonaDetail(name);
        }
        else result = null;
      }
      // POST routes
      else if (method === 'POST') {
        let body;
        try {
          body = await parseBody(req);
        } catch (e) {
          const er = err(e.message, 400);
          res.writeHead(er.statusCode);
          res.end(er.body);
          return;
        }

        if (pathname === '/api/switch') result = await handlePostSwitch(body);
        else if (pathname === '/api/config') result = await handlePostConfig(body);
        else if (pathname === '/api/build') result = await handlePostBuild(body);
        else if (pathname === '/api/install') result = await handlePostInstall(body);
        else if (pathname === '/api/init') result = await handlePostInit(body);
        else if (pathname === '/api/doctor') result = await handlePostDoctor();
        else if (pathname === '/api/diff') result = await handlePostDiff();
        else if (pathname === '/api/dashboard/scan') result = await handlePostDashboardScan(body);
        else result = null;
      }
      // DELETE routes
      else if (method === 'DELETE') {
        if (pathname.match(/^\/api\/personas\/[^/]+$/)) {
          const name = decodeURIComponent(pathname.split('/').pop());
          result = handleDeletePersona(name);
        } else {
          result = null;
        }
      }
    } catch (e) {
      const er = err('Internal error: ' + e.message, 500);
      res.writeHead(er.statusCode);
      res.end(er.body);
      return;
    }

    if (result === null) {
      res.writeHead(404);
      res.end(JSON.stringify({ ok: false, data: null, error: 'Not found' }));
      return;
    }

    // result can be a string (success) or { body, statusCode } (error)
    if (typeof result === 'string') {
      res.writeHead(200);
      res.end(result);
    } else {
      res.writeHead(result.statusCode || 500);
      res.end(result.body);
    }
    return;
  }

  // 404 for everything else
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found');
}

// ── Server Lifecycle ──────────────────────────────────────────

const requestedPort = parseInt(process.env.FORGE_UI_PORT || '0', 10) || 0;

const server = http.createServer(handleRequest);

server.listen(requestedPort, '127.0.0.1', () => {
  const addr = server.address();
  const port = addr.port;

  // Write lifecycle files
  fs.mkdirSync(CLAUDE_DIR, { recursive: true });
  fs.writeFileSync(PID_FILE, String(process.pid));
  fs.writeFileSync(PORT_FILE, String(port));
  fs.writeFileSync(TOKEN_FILE, SESSION_TOKEN, { mode: 0o600 });

  // Output for the CLI to read
  console.log(JSON.stringify({ port, token: SESSION_TOKEN, pid: process.pid }));
});

server.on('error', (e) => {
  console.error('Server error:', e.message);
  process.exit(1);
});

function cleanup() {
  try { fs.unlinkSync(PID_FILE); } catch {}
  try { fs.unlinkSync(PORT_FILE); } catch {}
  try { fs.unlinkSync(TOKEN_FILE); } catch {}
  server.close();
}

process.on('SIGTERM', () => { cleanup(); process.exit(0); });
process.on('SIGINT', () => { cleanup(); process.exit(0); });
process.on('exit', cleanup);
