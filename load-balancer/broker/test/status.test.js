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
