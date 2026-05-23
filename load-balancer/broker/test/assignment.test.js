const { describe, it, beforeEach, afterEach } = require('node:test');
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
