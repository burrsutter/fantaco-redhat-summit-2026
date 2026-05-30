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
      '# public_host,openshift_route_host,enabled,namespace,token_fragment',
      'claw-new-111.yougetaclaw.com,claw-new-111.apps.ocp.example.com,true,agentic-user1,#token=new111',
      'claw-new-222.yougetaclaw.com,claw-new-222.apps.ocp.example.com,true,agentic-user2,#token=new222',
    ].join('\n'));

    db.loadRoutes([
      { public_host: 'claw-old-aaa.yougetaclaw.com', backend_host: 'claw-old-aaa.apps.ocp.example.com', enabled: true, token_fragment: '#token=oldaaa' },
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

  describe('admin lockdown', () => {
    it('blocks /admin/reset when X-Forwarded-For is present', async () => {
      const res = await request(server, {
        method: 'POST',
        path: '/admin/reset',
        headers: { 'x-forwarded-for': '1.2.3.4' },
      });
      assert.equal(res.status, 403);
      assert.equal(res.json.error, 'admin access denied');
    });

    it('blocks /admin/release when X-Forwarded-For is present', async () => {
      const res = await request(server, {
        method: 'POST',
        path: '/admin/release/1',
        headers: { 'x-forwarded-for': '1.2.3.4' },
      });
      assert.equal(res.status, 403);
      assert.equal(res.json.error, 'admin access denied');
    });

    it('allows /admin/reset without X-Forwarded-For', async () => {
      const res = await request(server, { method: 'POST', path: '/admin/reset' });
      assert.equal(res.status, 200);
    });
  });
});
