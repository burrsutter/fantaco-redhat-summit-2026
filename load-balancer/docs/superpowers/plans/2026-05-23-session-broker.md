# Session Broker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Node.js session broker that assigns each visitor to `yougetaclaw.com` an exclusive OpenClaw Gateway route via cookie + 302 redirect, with a read-only status board.

**Architecture:** Express service on the HAProxy EC2 instance (port 3000). HAProxy ACL forwards bare-domain requests to the broker. The broker assigns routes from a SQLite-backed pool loaded from `routes.csv`, sets a cookie, and redirects. After redirect, HAProxy map routing handles all subsequent traffic directly — broker is out of the data path.

**Tech Stack:** Node.js 22, Express, better-sqlite3, uuid, cookie-parser

**Spec:** `docs/superpowers/specs/2026-05-23-session-broker-design.md`

---

## File Structure

```
broker/
├── package.json              — dependencies and scripts
├── server.js                 — entry point: create app, listen on PORT
├── app.js                    — Express app factory (exported for testing)
├── db.js                     — SQLite initialization, schema, query helpers
├── routes-csv.js             — parse routes.csv into route objects
├── pages/
│   ├── full-house.html       — 503 "all seats taken" page
│   └── status.html           — status board HTML (fetches /status/api)
└── test/
    ├── db.test.js            — database layer tests
    ├── routes-csv.test.js    — CSV parser tests
    ├── assignment.test.js    — session assignment logic tests
    ├── admin.test.js         — admin reset/release endpoint tests
    └── status.test.js        — status board API tests
```

Integration files (modified):

```
scripts/08-launch-ec2.sh      — add broker install + systemd service to user-data
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `broker/package.json`
- Create: `broker/.gitignore`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "route-lb-broker",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node server.js",
    "test": "node --test test/*.test.js"
  },
  "dependencies": {
    "better-sqlite3": "^11.0.0",
    "cookie-parser": "^1.4.7",
    "express": "^4.21.0",
    "uuid": "^11.0.0"
  }
}
```

- [ ] **Step 2: Create .gitignore**

```
node_modules/
*.db
*.db-wal
*.db-shm
```

- [ ] **Step 3: Install dependencies**

Run: `cd broker && npm install`
Expected: `node_modules/` created, `package-lock.json` generated.

- [ ] **Step 4: Commit**

```bash
git add broker/package.json broker/package-lock.json broker/.gitignore
git commit -m "feat(broker): scaffold project with dependencies"
```

---

### Task 2: CSV Parser

**Files:**
- Create: `broker/routes-csv.js`
- Create: `broker/test/routes-csv.test.js`

- [ ] **Step 1: Write the failing test**

Create `broker/test/routes-csv.test.js`:

```javascript
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parseRoutesCsv } = require('../routes-csv');

describe('parseRoutesCsv', () => {
  it('parses enabled routes', () => {
    const csv = [
      '# public_host,openshift_route_host,enabled',
      'claw-abc-def123.yougetaclaw.com,claw-abc-def123.apps.ocp.example.com,true',
      'claw-abc-aaa111.yougetaclaw.com,claw-abc-aaa111.apps.ocp.example.com,true',
    ].join('\n');

    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 2);
    assert.deepEqual(routes[0], {
      public_host: 'claw-abc-def123.yougetaclaw.com',
      backend_host: 'claw-abc-def123.apps.ocp.example.com',
      enabled: true,
    });
  });

  it('skips disabled routes', () => {
    const csv = [
      'claw-abc-def123.yougetaclaw.com,claw-abc-def123.apps.ocp.example.com,false',
      'claw-abc-aaa111.yougetaclaw.com,claw-abc-aaa111.apps.ocp.example.com,true',
    ].join('\n');

    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 1);
    assert.equal(routes[0].public_host, 'claw-abc-aaa111.yougetaclaw.com');
  });

  it('skips comments and blank lines', () => {
    const csv = [
      '# this is a comment',
      '',
      '  ',
      'claw-abc-def123.yougetaclaw.com,claw-abc-def123.apps.ocp.example.com,true',
    ].join('\n');

    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 1);
  });

  it('trims whitespace from fields', () => {
    const csv = '  claw-abc-def123.yougetaclaw.com , claw-abc-def123.apps.ocp.example.com , true  ';
    const routes = parseRoutesCsv(csv);
    assert.equal(routes[0].public_host, 'claw-abc-def123.yougetaclaw.com');
    assert.equal(routes[0].backend_host, 'claw-abc-def123.apps.ocp.example.com');
  });

  it('lowercases hostnames', () => {
    const csv = 'CLAW-ABC-DEF123.yougetaclaw.com,CLAW-ABC-DEF123.apps.ocp.example.com,TRUE';
    const routes = parseRoutesCsv(csv);
    assert.equal(routes[0].public_host, 'claw-abc-def123.yougetaclaw.com');
    assert.equal(routes[0].enabled, true);
  });

  it('rejects invalid hostnames', () => {
    const csv = 'not a valid host!,also bad!,true';
    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 0);
  });

  it('returns empty array for empty input', () => {
    assert.deepEqual(parseRoutesCsv(''), []);
    assert.deepEqual(parseRoutesCsv('# only comments'), []);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd broker && node --test test/routes-csv.test.js`
Expected: FAIL — `Cannot find module '../routes-csv'`

- [ ] **Step 3: Write the implementation**

Create `broker/routes-csv.js`:

```javascript
'use strict';

const HOSTNAME_RE = /^[a-z0-9.-]+$/;

function parseRoutesCsv(text) {
  const routes = [];

  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;

    const parts = line.split(',');
    if (parts.length < 3) continue;

    const public_host = parts[0].trim().toLowerCase();
    const backend_host = parts[1].trim().toLowerCase();
    const enabled = parts[2].trim().toLowerCase() === 'true';

    if (!HOSTNAME_RE.test(public_host) || !HOSTNAME_RE.test(backend_host)) continue;

    routes.push({ public_host, backend_host, enabled });
  }

  return routes.filter(r => r.enabled);
}

module.exports = { parseRoutesCsv };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd broker && node --test test/routes-csv.test.js`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add broker/routes-csv.js broker/test/routes-csv.test.js
git commit -m "feat(broker): add routes.csv parser with tests"
```

---

### Task 3: Database Layer

**Files:**
- Create: `broker/db.js`
- Create: `broker/test/db.test.js`

- [ ] **Step 1: Write the failing test**

Create `broker/test/db.test.js`:

```javascript
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { createDb } = require('../db');

describe('database', () => {
  let db;

  beforeEach(() => {
    db = createDb(':memory:');
  });

  describe('loadRoutes', () => {
    it('inserts routes and clears previous data', () => {
      const routes = [
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true },
        { public_host: 'b.example.com', backend_host: 'b.ocp.example.com', enabled: true },
      ];
      db.loadRoutes(routes, 'abc12');
      const all = db.getAllRoutes();
      assert.equal(all.length, 2);
      assert.equal(all[0].public_host, 'a.example.com');
    });

    it('replaces routes on second load', () => {
      db.loadRoutes([
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true },
      ], 'abc12');
      db.loadRoutes([
        { public_host: 'x.example.com', backend_host: 'x.ocp.example.com', enabled: true },
      ], 'def34');
      const all = db.getAllRoutes();
      assert.equal(all.length, 1);
      assert.equal(all[0].public_host, 'x.example.com');
    });
  });

  describe('assignment', () => {
    beforeEach(() => {
      db.loadRoutes([
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true },
        { public_host: 'b.example.com', backend_host: 'b.ocp.example.com', enabled: true },
      ], 'abc12');
    });

    it('assigns first available route', () => {
      const route = db.assignRoute('cookie-1');
      assert.equal(route.public_host, 'a.example.com');
    });

    it('assigns different routes to different cookies', () => {
      const r1 = db.assignRoute('cookie-1');
      const r2 = db.assignRoute('cookie-2');
      assert.notEqual(r1.public_host, r2.public_host);
    });

    it('returns null when all routes assigned', () => {
      db.assignRoute('cookie-1');
      db.assignRoute('cookie-2');
      const r3 = db.assignRoute('cookie-3');
      assert.equal(r3, null);
    });

    it('looks up existing assignment by cookie', () => {
      db.assignRoute('cookie-1');
      const found = db.findAssignment('cookie-1');
      assert.equal(found.public_host, 'a.example.com');
    });

    it('returns null for unknown cookie', () => {
      const found = db.findAssignment('unknown');
      assert.equal(found, null);
    });
  });

  describe('release', () => {
    beforeEach(() => {
      db.loadRoutes([
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true },
      ], 'abc12');
    });

    it('releases an assignment by route id', () => {
      db.assignRoute('cookie-1');
      const routes = db.getAllRoutes();
      db.releaseRoute(routes[0].id);
      const found = db.findAssignment('cookie-1');
      assert.equal(found, null);
    });
  });

  describe('reset', () => {
    it('clears all assignments', () => {
      db.loadRoutes([
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true },
      ], 'abc12');
      db.assignRoute('cookie-1');
      db.resetAssignments();
      const found = db.findAssignment('cookie-1');
      assert.equal(found, null);
    });
  });

  describe('stats', () => {
    it('returns correct counts', () => {
      db.loadRoutes([
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true },
        { public_host: 'b.example.com', backend_host: 'b.ocp.example.com', enabled: true },
        { public_host: 'c.example.com', backend_host: 'c.ocp.example.com', enabled: true },
      ], 'abc12');
      db.assignRoute('cookie-1');

      const stats = db.getStats();
      assert.equal(stats.total, 3);
      assert.equal(stats.assigned, 1);
      assert.equal(stats.available, 2);
      assert.equal(stats.audience_id, 'abc12');
    });

    it('returns zeroes when no routes loaded', () => {
      const stats = db.getStats();
      assert.equal(stats.total, 0);
      assert.equal(stats.assigned, 0);
      assert.equal(stats.available, 0);
      assert.equal(stats.audience_id, null);
    });
  });

  describe('getRoutesWithStatus', () => {
    it('shows assignment status per route', () => {
      db.loadRoutes([
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true },
        { public_host: 'b.example.com', backend_host: 'b.ocp.example.com', enabled: true },
      ], 'abc12');
      db.assignRoute('cookie-1');

      const rows = db.getRoutesWithStatus();
      assert.equal(rows.length, 2);
      assert.equal(rows[0].assigned, 1);
      assert.ok(rows[0].assigned_at);
      assert.equal(rows[1].assigned, 0);
      assert.equal(rows[1].assigned_at, null);
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd broker && node --test test/db.test.js`
Expected: FAIL — `Cannot find module '../db'`

- [ ] **Step 3: Write the implementation**

Create `broker/db.js`:

```javascript
'use strict';

const Database = require('better-sqlite3');

function createDb(dbPath) {
  const sqlite = new Database(dbPath);
  sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('foreign_keys = ON');

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS routes (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      public_host   TEXT NOT NULL UNIQUE,
      backend_host  TEXT NOT NULL,
      enabled       INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS assignments (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      cookie_value  TEXT NOT NULL UNIQUE,
      route_id      INTEGER NOT NULL REFERENCES routes(id),
      assigned_at   TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS audiences (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      audience_id   TEXT,
      started_at    TEXT NOT NULL DEFAULT (datetime('now')),
      active        INTEGER NOT NULL DEFAULT 1
    );
  `);

  const stmts = {
    insertRoute: sqlite.prepare(
      'INSERT INTO routes (public_host, backend_host, enabled) VALUES (?, ?, ?)'
    ),
    deleteAllRoutes: sqlite.prepare('DELETE FROM routes'),
    deleteAllAssignments: sqlite.prepare('DELETE FROM assignments'),
    deactivateAudiences: sqlite.prepare('UPDATE audiences SET active = 0'),
    insertAudience: sqlite.prepare(
      'INSERT INTO audiences (audience_id, active) VALUES (?, 1)'
    ),
    findAvailable: sqlite.prepare(`
      SELECT r.id, r.public_host, r.backend_host FROM routes r
      LEFT JOIN assignments a ON a.route_id = r.id
      WHERE r.enabled = 1 AND a.id IS NULL
      ORDER BY r.id LIMIT 1
    `),
    insertAssignment: sqlite.prepare(
      'INSERT INTO assignments (cookie_value, route_id) VALUES (?, ?)'
    ),
    findByCookie: sqlite.prepare(`
      SELECT r.id, r.public_host, r.backend_host FROM assignments a
      JOIN routes r ON r.id = a.route_id
      WHERE a.cookie_value = ?
    `),
    releaseByRouteId: sqlite.prepare(
      'DELETE FROM assignments WHERE route_id = ?'
    ),
    allRoutes: sqlite.prepare('SELECT * FROM routes ORDER BY id'),
    routesWithStatus: sqlite.prepare(`
      SELECT r.id, r.public_host, r.backend_host, r.enabled,
             CASE WHEN a.id IS NOT NULL THEN 1 ELSE 0 END as assigned,
             a.assigned_at
      FROM routes r
      LEFT JOIN assignments a ON a.route_id = r.id
      ORDER BY r.id
    `),
    countTotal: sqlite.prepare(
      'SELECT COUNT(*) as n FROM routes WHERE enabled = 1'
    ),
    countAssigned: sqlite.prepare(`
      SELECT COUNT(*) as n FROM assignments a
      JOIN routes r ON r.id = a.route_id WHERE r.enabled = 1
    `),
    activeAudience: sqlite.prepare(
      'SELECT audience_id, started_at FROM audiences WHERE active = 1 ORDER BY id DESC LIMIT 1'
    ),
  };

  const loadRoutes = sqlite.transaction((routes, audienceId) => {
    stmts.deleteAllAssignments.run();
    stmts.deleteAllRoutes.run();
    stmts.deactivateAudiences.run();
    for (const r of routes) {
      stmts.insertRoute.run(r.public_host, r.backend_host, r.enabled ? 1 : 0);
    }
    if (audienceId) {
      stmts.insertAudience.run(audienceId);
    }
  });

  return {
    loadRoutes,

    assignRoute(cookieValue) {
      const route = stmts.findAvailable.get();
      if (!route) return null;
      stmts.insertAssignment.run(cookieValue, route.id);
      return route;
    },

    findAssignment(cookieValue) {
      return stmts.findByCookie.get(cookieValue) || null;
    },

    releaseRoute(routeId) {
      stmts.releaseByRouteId.run(routeId);
    },

    resetAssignments() {
      stmts.deleteAllAssignments.run();
    },

    getAllRoutes() {
      return stmts.allRoutes.all();
    },

    getRoutesWithStatus() {
      return stmts.routesWithStatus.all();
    },

    getStats() {
      const total = stmts.countTotal.get().n;
      const assigned = stmts.countAssigned.get().n;
      const audience = stmts.activeAudience.get();
      return {
        total,
        assigned,
        available: total - assigned,
        audience_id: audience ? audience.audience_id : null,
        audience_started: audience ? audience.started_at : null,
      };
    },

    close() {
      sqlite.close();
    },
  };
}

module.exports = { createDb };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd broker && node --test test/db.test.js`
Expected: All 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add broker/db.js broker/test/db.test.js
git commit -m "feat(broker): add SQLite database layer with tests"
```

---

### Task 4: Session Assignment Endpoint (GET /)

**Files:**
- Create: `broker/app.js`
- Create: `broker/pages/full-house.html`
- Create: `broker/test/assignment.test.js`

- [ ] **Step 1: Write the failing test**

Create `broker/test/assignment.test.js`:

```javascript
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createApp } = require('../app');
const { createDb } = require('../db');

function request(server, { path = '/', headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, `http://localhost:${server.address().port}`);
    const req = http.get(url, { headers }, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
    });
    req.on('error', reject);
  });
}

describe('GET / (session assignment)', () => {
  let db, app, server;

  beforeEach(async () => {
    db = createDb(':memory:');
    app = createApp({ db, cookieDomain: 'yougetaclaw.com' });
    server = app.listen(0);
    await new Promise((r) => server.on('listening', r));
  });

  beforeEach(() => {
    db.loadRoutes([
      { public_host: 'claw-abc-111.yougetaclaw.com', backend_host: 'claw-abc-111.apps.ocp.example.com', enabled: true },
      { public_host: 'claw-abc-222.yougetaclaw.com', backend_host: 'claw-abc-222.apps.ocp.example.com', enabled: true },
    ], 'abc');
  });

  it('redirects new user to an available route', async () => {
    const res = await request(server, { path: '/' });
    assert.equal(res.status, 302);
    assert.ok(res.headers.location.startsWith('https://claw-abc-'));
    assert.ok(res.headers['set-cookie'][0].includes('rlb_session='));
  });

  it('redirects returning user to their assigned route', async () => {
    const res1 = await request(server, { path: '/' });
    const cookie = res1.headers['set-cookie'][0].split(';')[0];

    const res2 = await request(server, { path: '/', headers: { cookie } });
    assert.equal(res2.status, 302);
    assert.equal(res2.headers.location, res1.headers.location);
  });

  it('returns 503 when all routes are assigned', async () => {
    await request(server, { path: '/' });
    await request(server, { path: '/' });
    const res = await request(server, { path: '/' });
    assert.equal(res.status, 503);
    assert.ok(res.body.includes('All seats are taken'));
  });

  it('treats stale cookie as new user', async () => {
    const res = await request(server, {
      path: '/',
      headers: { cookie: 'rlb_session=stale-value-from-previous-audience' },
    });
    assert.equal(res.status, 302);
    assert.ok(res.headers['set-cookie'][0].includes('rlb_session='));
  });

  afterEach(() => {
    server.close();
    db.close();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd broker && node --test test/assignment.test.js`
Expected: FAIL — `Cannot find module '../app'`

- [ ] **Step 3: Create the full-house HTML page**

Create `broker/pages/full-house.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>You Get a Claw</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0a0a1a;
      color: #e0e0e0;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .card {
      text-align: center;
      max-width: 480px;
    }
    h1 { font-size: 2rem; margin-bottom: 12px; color: #ff6b6b; }
    p { font-size: 1.1rem; line-height: 1.6; color: #aaa; }
  </style>
</head>
<body>
  <div class="card">
    <h1>All seats are taken</h1>
    <p>All seats are taken for this session.<br>Please check with the presenter.</p>
  </div>
</body>
</html>
```

- [ ] **Step 4: Write the app**

Create `broker/app.js`:

```javascript
'use strict';

const express = require('express');
const cookieParser = require('cookie-parser');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');

const FULL_HOUSE_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'full-house.html'),
  'utf8'
);

function createApp({ db, cookieDomain }) {
  const app = express();
  app.use(cookieParser());

  // Session assignment
  app.get('/', (req, res) => {
    const existingCookie = req.cookies.rlb_session;

    // Check for returning user
    if (existingCookie) {
      const assignment = db.findAssignment(existingCookie);
      if (assignment) {
        return res.redirect(302, `https://${assignment.public_host}`);
      }
      // Stale cookie — fall through to assign a new route
    }

    // New user (or stale cookie) — assign a route
    const cookieValue = uuidv4();
    const route = db.assignRoute(cookieValue);

    if (!route) {
      return res.status(503).send(FULL_HOUSE_HTML);
    }

    res.cookie('rlb_session', cookieValue, {
      domain: cookieDomain,
      path: '/',
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
      maxAge: 86400 * 1000,
    });

    return res.redirect(302, `https://${route.public_host}`);
  });

  return app;
}

module.exports = { createApp };
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd broker && node --test test/assignment.test.js`
Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add broker/app.js broker/pages/full-house.html broker/test/assignment.test.js
git commit -m "feat(broker): add session assignment endpoint with redirect"
```

---

### Task 5: Admin Endpoints (POST /admin/reset, POST /admin/release/:slot)

**Files:**
- Modify: `broker/app.js`
- Create: `broker/test/admin.test.js`

- [ ] **Step 1: Write the failing test**

Create `broker/test/admin.test.js`:

```javascript
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { createApp } = require('../app');
const { createDb } = require('../db');

function request(server, { method = 'GET', path: reqPath = '/', headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(reqPath, `http://localhost:${server.address().port}`);
    const req = http.request(url, { method, headers }, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => {
        let json;
        try { json = JSON.parse(body); } catch {}
        resolve({ status: res.statusCode, headers: res.headers, body, json });
      });
    });
    req.on('error', reject);
    req.end();
  });
}

describe('admin endpoints', () => {
  let db, app, server, csvPath;

  beforeEach(async () => {
    db = createDb(':memory:');
    csvPath = path.join(os.tmpdir(), `test-routes-${Date.now()}.csv`);
    fs.writeFileSync(csvPath, [
      '# public_host,openshift_route_host,enabled',
      'claw-new-111.yougetaclaw.com,claw-new-111.apps.ocp.example.com,true',
      'claw-new-222.yougetaclaw.com,claw-new-222.apps.ocp.example.com,true',
    ].join('\n'));

    db.loadRoutes([
      { public_host: 'claw-old-aaa.yougetaclaw.com', backend_host: 'claw-old-aaa.apps.ocp.example.com', enabled: true },
    ], 'old');

    app = createApp({ db, cookieDomain: 'yougetaclaw.com', routesCsvPath: csvPath });
    server = app.listen(0);
    await new Promise((r) => server.on('listening', r));
  });

  afterEach(() => {
    server.close();
    db.close();
    try { fs.unlinkSync(csvPath); } catch {}
  });

  describe('POST /admin/reset', () => {
    it('clears assignments and loads new routes from CSV', async () => {
      // Assign a route first
      db.assignRoute('cookie-1');
      assert.ok(db.findAssignment('cookie-1'));

      const res = await request(server, { method: 'POST', path: '/admin/reset' });
      assert.equal(res.status, 200);

      // Old assignment is gone
      assert.equal(db.findAssignment('cookie-1'), null);

      // New routes loaded
      const routes = db.getAllRoutes();
      assert.equal(routes.length, 2);
      assert.equal(routes[0].public_host, 'claw-new-111.yougetaclaw.com');
    });

    it('extracts audience id from route hostnames', async () => {
      await request(server, { method: 'POST', path: '/admin/reset' });
      const stats = db.getStats();
      assert.equal(stats.audience_id, 'new');
    });
  });

  describe('POST /admin/release/:slot', () => {
    it('releases assignment for the given route id', async () => {
      db.assignRoute('cookie-1');
      const routes = db.getAllRoutes();

      const res = await request(server, {
        method: 'POST',
        path: `/admin/release/${routes[0].id}`,
      });
      assert.equal(res.status, 200);
      assert.equal(db.findAssignment('cookie-1'), null);
    });

    it('returns 404 for unknown route id', async () => {
      const res = await request(server, {
        method: 'POST',
        path: '/admin/release/9999',
      });
      assert.equal(res.status, 404);
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd broker && node --test test/admin.test.js`
Expected: FAIL — 404 on `/admin/reset` (route not defined yet).

- [ ] **Step 3: Add admin routes to app.js**

Add the following to `broker/app.js`, inside `createApp` before the `return app` line:

```javascript
  app.use(express.json());

  // Admin: reset all assignments and reload routes from CSV
  app.post('/admin/reset', (req, res) => {
    if (!routesCsvPath) {
      return res.status(500).json({ error: 'no routesCsvPath configured' });
    }

    let csvText;
    try {
      csvText = fs.readFileSync(routesCsvPath, 'utf8');
    } catch (err) {
      return res.status(500).json({ error: `failed to read ${routesCsvPath}: ${err.message}` });
    }

    const routes = parseRoutesCsv(csvText);
    if (routes.length === 0) {
      return res.status(400).json({ error: 'no enabled routes found in CSV' });
    }

    // Extract audience ID from first route: claw-{audience}-{user}.domain
    const match = routes[0].public_host.match(/^claw-([a-z0-9]+)-/);
    const audienceId = match ? match[1] : null;

    db.loadRoutes(routes, audienceId);
    const stats = db.getStats();
    res.json({ ok: true, ...stats });
  });

  // Admin: release a single assignment
  app.post('/admin/release/:slot', (req, res) => {
    const routeId = parseInt(req.params.slot, 10);
    const routes = db.getAllRoutes();
    const route = routes.find((r) => r.id === routeId);
    if (!route) {
      return res.status(404).json({ error: 'route not found' });
    }
    db.releaseRoute(routeId);
    res.json({ ok: true, released: route.public_host });
  });
```

Also update the `createApp` function signature to accept `routesCsvPath`:

```javascript
function createApp({ db, cookieDomain, routesCsvPath }) {
```

And add the import at the top of the file:

```javascript
const { parseRoutesCsv } = require('./routes-csv');
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd broker && node --test test/admin.test.js`
Expected: All 4 tests pass.

- [ ] **Step 5: Run all tests to check nothing broke**

Run: `cd broker && node --test test/*.test.js`
Expected: All tests pass (assignment tests still pass since `routesCsvPath` is optional).

- [ ] **Step 6: Commit**

```bash
git add broker/app.js broker/test/admin.test.js
git commit -m "feat(broker): add admin reset and release endpoints"
```

---

### Task 6: Status Board

**Files:**
- Create: `broker/pages/status.html`
- Modify: `broker/app.js`
- Create: `broker/test/status.test.js`

- [ ] **Step 1: Write the failing test**

Create `broker/test/status.test.js`:

```javascript
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createApp } = require('../app');
const { createDb } = require('../db');

function request(server, { path: reqPath = '/' } = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(reqPath, `http://localhost:${server.address().port}`);
    http.get(url, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => {
        let json;
        try { json = JSON.parse(body); } catch {}
        resolve({ status: res.statusCode, headers: res.headers, body, json });
      });
    }).on('error', reject);
  });
}

describe('status board', () => {
  let db, app, server;

  beforeEach(async () => {
    db = createDb(':memory:');
    db.loadRoutes([
      { public_host: 'claw-abc-111.yougetaclaw.com', backend_host: 'claw-abc-111.apps.ocp.example.com', enabled: true },
      { public_host: 'claw-abc-222.yougetaclaw.com', backend_host: 'claw-abc-222.apps.ocp.example.com', enabled: true },
    ], 'abc');
    db.assignRoute('cookie-1');
    app = createApp({ db, cookieDomain: 'yougetaclaw.com' });
    server = app.listen(0);
    await new Promise((r) => server.on('listening', r));
  });

  afterEach(() => {
    server.close();
    db.close();
  });

  describe('GET /status/api', () => {
    it('returns JSON with stats and routes', async () => {
      const res = await request(server, { path: '/status/api' });
      assert.equal(res.status, 200);
      assert.equal(res.json.stats.total, 2);
      assert.equal(res.json.stats.assigned, 1);
      assert.equal(res.json.stats.available, 1);
      assert.equal(res.json.stats.audience_id, 'abc');
      assert.equal(res.json.routes.length, 2);
      assert.equal(res.json.routes[0].assigned, 1);
      assert.equal(res.json.routes[1].assigned, 0);
    });
  });

  describe('GET /status', () => {
    it('returns HTML page', async () => {
      const res = await request(server, { path: '/status' });
      assert.equal(res.status, 200);
      assert.ok(res.headers['content-type'].includes('text/html'));
      assert.ok(res.body.includes('Route-LB Status'));
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd broker && node --test test/status.test.js`
Expected: FAIL — 404 on `/status/api` and `/status`.

- [ ] **Step 3: Create status board HTML**

Create `broker/pages/status.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Route-LB Status</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0a0a1a;
      color: #e0e0e0;
      padding: 24px;
      max-width: 1200px;
      margin: 0 auto;
    }
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 24px;
      flex-wrap: wrap;
      gap: 16px;
    }
    h1 { font-size: 1.5rem; }
    .audience { color: #888; font-size: 0.9rem; }
    .audience code { color: #64ffda; }
    .counters {
      display: flex;
      gap: 32px;
      text-align: center;
    }
    .counter-value {
      font-size: 2.5rem;
      font-weight: bold;
      line-height: 1;
    }
    .counter-label {
      font-size: 0.7rem;
      color: #888;
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-top: 4px;
    }
    .assigned-color { color: #64ffda; }
    .available-color { color: #ffd93d; }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.85rem;
    }
    th {
      text-align: left;
      padding: 8px;
      color: #888;
      border-bottom: 1px solid #333;
      font-weight: normal;
    }
    td {
      padding: 8px;
      border-bottom: 1px solid #1a1a2e;
      font-family: 'SF Mono', 'Consolas', monospace;
      font-size: 0.8rem;
    }
    .status-assigned { color: #64ffda; }
    .status-available { color: #ffd93d; }
    .refresh-note {
      margin-top: 16px;
      color: #555;
      font-size: 0.75rem;
    }
    .no-routes {
      text-align: center;
      padding: 48px;
      color: #555;
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>Route-LB Status</h1>
      <div class="audience">Audience: <code id="audience-id">—</code> · Started <span id="audience-started">—</span></div>
    </div>
    <div class="counters">
      <div>
        <div class="counter-value assigned-color" id="count-assigned">—</div>
        <div class="counter-label">Assigned</div>
      </div>
      <div>
        <div class="counter-value available-color" id="count-available">—</div>
        <div class="counter-label">Available</div>
      </div>
    </div>
  </header>

  <table>
    <thead>
      <tr>
        <th>#</th>
        <th>Public Host</th>
        <th>Backend Route</th>
        <th>Status</th>
        <th>Assigned At</th>
      </tr>
    </thead>
    <tbody id="route-table"></tbody>
  </table>
  <div class="refresh-note">Auto-refreshes every 5 seconds</div>

  <script>
    async function refresh() {
      try {
        const res = await fetch('/status/api');
        const data = await res.json();

        document.getElementById('audience-id').textContent = data.stats.audience_id || '—';
        document.getElementById('audience-started').textContent = data.stats.audience_started || '—';
        document.getElementById('count-assigned').textContent = data.stats.assigned;
        document.getElementById('count-available').textContent = data.stats.available;

        const tbody = document.getElementById('route-table');
        if (data.routes.length === 0) {
          tbody.innerHTML = '<tr><td colspan="5" class="no-routes">No routes loaded</td></tr>';
          return;
        }

        tbody.innerHTML = data.routes.map((r, i) => `
          <tr>
            <td>${String(i + 1).padStart(3, '0')}</td>
            <td>${r.public_host}</td>
            <td style="color:#666">${r.backend_host}</td>
            <td class="${r.assigned ? 'status-assigned' : 'status-available'}">
              ${r.assigned ? '● assigned' : '○ available'}
            </td>
            <td style="color:#666">${r.assigned_at || '—'}</td>
          </tr>
        `).join('');
      } catch (err) {
        console.error('refresh failed:', err);
      }
    }

    refresh();
    setInterval(refresh, 5000);
  </script>
</body>
</html>
```

- [ ] **Step 4: Add status routes to app.js**

Add the following to `broker/app.js`, inside `createApp` before the admin routes:

```javascript
  const STATUS_HTML = fs.readFileSync(
    path.join(__dirname, 'pages', 'status.html'),
    'utf8'
  );

  // Status board — HTML page
  app.get('/status', (req, res) => {
    res.type('html').send(STATUS_HTML);
  });

  // Status board — JSON API
  app.get('/status/api', (req, res) => {
    const stats = db.getStats();
    const routes = db.getRoutesWithStatus();
    res.json({ stats, routes });
  });
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd broker && node --test test/status.test.js`
Expected: All 2 tests pass.

- [ ] **Step 6: Run all tests**

Run: `cd broker && node --test test/*.test.js`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add broker/pages/status.html broker/app.js broker/test/status.test.js
git commit -m "feat(broker): add status board HTML and JSON API"
```

---

### Task 7: Server Entry Point

**Files:**
- Create: `broker/server.js`

- [ ] **Step 1: Write server.js**

Create `broker/server.js`:

```javascript
'use strict';

const fs = require('fs');
const { createDb } = require('./db');
const { createApp } = require('./app');
const { parseRoutesCsv } = require('./routes-csv');

const PORT = parseInt(process.env.PORT || '3000', 10);
const DB_PATH = process.env.DB_PATH || './broker.db';
const ROUTES_CSV_PATH = process.env.ROUTES_CSV_PATH || './routes.csv';
const COOKIE_DOMAIN = process.env.COOKIE_DOMAIN || 'yougetaclaw.com';

const db = createDb(DB_PATH);

// If the routes table is empty, try to load from CSV
const existingRoutes = db.getAllRoutes();
if (existingRoutes.length === 0) {
  try {
    const csvText = fs.readFileSync(ROUTES_CSV_PATH, 'utf8');
    const routes = parseRoutesCsv(csvText);
    if (routes.length > 0) {
      const match = routes[0].public_host.match(/^claw-([a-z0-9]+)-/);
      const audienceId = match ? match[1] : null;
      db.loadRoutes(routes, audienceId);
      console.log(`Loaded ${routes.length} routes from ${ROUTES_CSV_PATH} (audience: ${audienceId})`);
    }
  } catch (err) {
    console.log(`No routes loaded on startup: ${err.message}`);
  }
}

const app = createApp({ db, cookieDomain: COOKIE_DOMAIN, routesCsvPath: ROUTES_CSV_PATH });

const server = app.listen(PORT, () => {
  const stats = db.getStats();
  console.log(`Route-LB broker listening on :${PORT}`);
  console.log(`  Routes: ${stats.total} (${stats.assigned} assigned, ${stats.available} available)`);
  console.log(`  Audience: ${stats.audience_id || 'none'}`);
  console.log(`  DB: ${DB_PATH}`);
  console.log(`  CSV: ${ROUTES_CSV_PATH}`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => {
    db.close();
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down...');
  server.close(() => {
    db.close();
    process.exit(0);
  });
});
```

- [ ] **Step 2: Verify it starts**

Run: `cd broker && PORT=3001 node server.js &`
Expected: Output includes `Route-LB broker listening on :3001` and `Routes: 0`.

Run: `curl -s http://localhost:3001/status/api | jq .`
Expected: `{"stats":{"total":0,"assigned":0,"available":0,"audience_id":null,"audience_started":null},"routes":[]}`

Run: `kill %1`

- [ ] **Step 3: Commit**

```bash
git add broker/server.js
git commit -m "feat(broker): add server entry point with startup route loading"
```

---

### Task 8: EC2 Deployment Script Update

**Files:**
- Modify: `scripts/08-launch-ec2.sh`

This task updates the EC2 user-data script to install and configure the broker alongside HAProxy.

- [ ] **Step 1: Read current 08-launch-ec2.sh**

Read `scripts/08-launch-ec2.sh` to locate the user-data section where HAProxy is configured.

- [ ] **Step 2: Add broker installation to user-data**

In the user-data section of `scripts/08-launch-ec2.sh`, after the HAProxy setup and before the route-lb-sync setup, add:

```bash
# ── Install Node.js and broker ──────────────────────────────────────
dnf install -y nodejs22

mkdir -p /opt/route-lb-broker /var/lib/route-lb

# Broker source files (packaged into user-data for MVP)
# Copy each broker source file into a heredoc.
# The file contents are defined in Tasks 1-7 of this plan.
# For each file below, paste the final contents from the corresponding task.

cat > /opt/route-lb-broker/package.json << 'BROKER_PKG'
# Paste contents of broker/package.json from Task 1
BROKER_PKG

cat > /opt/route-lb-broker/routes-csv.js << 'BROKER_CSV'
# Paste contents of broker/routes-csv.js from Task 2
BROKER_CSV

cat > /opt/route-lb-broker/db.js << 'BROKER_DB'
# Paste contents of broker/db.js from Task 3
BROKER_DB

cat > /opt/route-lb-broker/app.js << 'BROKER_APP'
# Paste contents of broker/app.js from Tasks 4-6 (final version with all routes)
BROKER_APP

cat > /opt/route-lb-broker/server.js << 'BROKER_SERVER'
# Paste contents of broker/server.js from Task 7
BROKER_SERVER

mkdir -p /opt/route-lb-broker/pages

cat > /opt/route-lb-broker/pages/full-house.html << 'BROKER_FULLHOUSE'
# Paste contents of broker/pages/full-house.html from Task 4
BROKER_FULLHOUSE

cat > /opt/route-lb-broker/pages/status.html << 'BROKER_STATUS'
# Paste contents of broker/pages/status.html from Task 6
BROKER_STATUS

cd /opt/route-lb-broker && npm install --production
```

- [ ] **Step 3: Add HAProxy broker backend to the haproxy.cfg section**

In the HAProxy config within the user-data, add the ACL and backend:

```haproxy
frontend http_in
    bind *:__HAPROXY_PORT__

    # Bare domain goes to broker
    acl is_bare_domain hdr(host) -i __DOMAIN__
    use_backend broker if is_bare_domain

    use_backend %[req.hdr(host),lower,map_str(/etc/haproxy/routes.map)]
    default_backend bk_default

backend bk_default
    http-request return status 503 content-type text/plain string "no route configured for this host"

backend broker
    server broker 127.0.0.1:3000

listen health
    bind *:8081
    http-request return status 200 content-type text/plain string "ready"
```

Replace `__DOMAIN__` with the `$DOMAIN` variable (like the existing `__HAPROXY_PORT__` replacement pattern).

- [ ] **Step 4: Add broker systemd service to user-data**

After the broker file installation, add:

```bash
cat > /etc/systemd/system/route-lb-broker.service << 'BROKER_UNIT'
[Unit]
Description=Route-LB Session Broker
After=network-online.target haproxy.service

[Service]
Type=simple
WorkingDirectory=/opt/route-lb-broker
ExecStart=/usr/bin/node server.js
Restart=always
Environment=PORT=3000
Environment=DB_PATH=/var/lib/route-lb/broker.db
Environment=ROUTES_CSV_PATH=/var/lib/route-lb/routes.csv
Environment=COOKIE_DOMAIN=yougetaclaw.com

[Install]
WantedBy=multi-user.target
BROKER_UNIT

systemctl daemon-reload
systemctl enable --now route-lb-broker
```

- [ ] **Step 5: Commit**

```bash
git add scripts/08-launch-ec2.sh
git commit -m "feat(broker): add broker deployment to EC2 user-data script"
```

---

### Task 9: End-to-End Smoke Test

**Files:**
- Create: `broker/test/smoke.sh`

- [ ] **Step 1: Write the smoke test script**

Create `broker/test/smoke.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Smoke test for the broker running locally
# Usage: ./test/smoke.sh [port]

PORT="${1:-3001}"
BASE="http://localhost:${PORT}"
PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Smoke Test (port $PORT) ==="

# 1. Status API — empty
echo ""
echo "--- Status API (empty) ---"
STATUS=$(curl -s "$BASE/status/api")
check "empty stats" '"total":0' "$STATUS"

# 2. Load test routes via admin reset
echo ""
echo "--- Load routes via CSV ---"
CSV_FILE=$(mktemp)
cat > "$CSV_FILE" <<EOF
# public_host,openshift_route_host,enabled
claw-test1-aaa.yougetaclaw.com,claw-test1-aaa.apps.ocp.example.com,true
claw-test1-bbb.yougetaclaw.com,claw-test1-bbb.apps.ocp.example.com,true
claw-test1-ccc.yougetaclaw.com,claw-test1-ccc.apps.ocp.example.com,true
EOF

# Copy to where the broker expects it
cp "$CSV_FILE" "${ROUTES_CSV_PATH:-./routes.csv}"
RESET=$(curl -s -X POST "$BASE/admin/reset")
check "reset loads 3 routes" '"total":3' "$RESET"
check "audience id extracted" '"audience_id":"test1"' "$RESET"

# 3. New user gets redirected
echo ""
echo "--- Session Assignment ---"
RESP=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" -c /tmp/smoke-cookies.jar "$BASE/")
HTTP_CODE=$(echo "$RESP" | cut -d' ' -f1)
REDIRECT_URL=$(echo "$RESP" | cut -d' ' -f2)
check "new user gets 302" "302" "$HTTP_CODE"
check "redirect to claw-test1" "claw-test1" "$REDIRECT_URL"

# 4. Returning user gets same redirect
RESP2=$(curl -s -o /dev/null -w "%{redirect_url}" -b /tmp/smoke-cookies.jar "$BASE/")
check "returning user same URL" "$REDIRECT_URL" "$RESP2"

# 5. Fill all slots
curl -s -o /dev/null -c /tmp/smoke-2.jar "$BASE/"
curl -s -o /dev/null -c /tmp/smoke-3.jar "$BASE/"

# 6. Next user gets 503
RESP_FULL=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/")
check "full house returns 503" "503" "$RESP_FULL"

# 7. Status shows 3 assigned
STATUS2=$(curl -s "$BASE/status/api")
check "3 assigned" '"assigned":3' "$STATUS2"
check "0 available" '"available":0' "$STATUS2"

# 8. Release one slot
ROUTE_ID=$(echo "$STATUS2" | python3 -c "import sys,json; print(json.load(sys.stdin)['routes'][0]['id'])")
RELEASE=$(curl -s -X POST "$BASE/admin/release/$ROUTE_ID")
check "release succeeds" '"ok":true' "$RELEASE"

# 9. Status shows 2 assigned
STATUS3=$(curl -s "$BASE/status/api")
check "2 assigned after release" '"assigned":2' "$STATUS3"

# 10. Status HTML page loads
STATUS_HTML=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status")
check "status page returns 200" "200" "$STATUS_HTML"

# Cleanup
rm -f /tmp/smoke-cookies.jar /tmp/smoke-2.jar /tmp/smoke-3.jar "$CSV_FILE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x broker/test/smoke.sh`

- [ ] **Step 3: Run the smoke test**

Run:
```bash
cd broker
PORT=3001 ROUTES_CSV_PATH=./routes.csv node server.js &
sleep 1
ROUTES_CSV_PATH=./routes.csv ./test/smoke.sh 3001
kill %1
```

Expected: All checks pass (10 passed, 0 failed).

- [ ] **Step 4: Commit**

```bash
git add broker/test/smoke.sh
git commit -m "test(broker): add end-to-end smoke test script"
```

---

## Summary

| Task | What it builds | Tests |
|------|---------------|-------|
| 1 | Project scaffolding | — |
| 2 | CSV parser | 7 unit tests |
| 3 | SQLite database layer | 12 unit tests |
| 4 | Session assignment (GET /) | 4 integration tests |
| 5 | Admin endpoints (reset, release) | 4 integration tests |
| 6 | Status board (HTML + JSON API) | 2 integration tests |
| 7 | Server entry point | Manual verify |
| 8 | EC2 deployment script | — |
| 9 | End-to-end smoke test | 10 checks |
