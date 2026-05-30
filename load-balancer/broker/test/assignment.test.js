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

describe('GET /:code (session assignment)', () => {
  let db, app, server;

  beforeEach(async () => {
    db = createDb(':memory:');
    app = createApp({ db, cookieDomain: 'yougetaclaw.com' });
    server = app.listen(0);
    await new Promise((r) => server.on('listening', r));
  });

  beforeEach(() => {
    db.loadRoutes([
      { public_host: 'claw-abc-111.yougetaclaw.com', backend_host: 'claw-abc-111.apps.ocp.example.com', enabled: true, token_fragment: '#token=tok111' },
      { public_host: 'claw-abc-222.yougetaclaw.com', backend_host: 'claw-abc-222.apps.ocp.example.com', enabled: true, token_fragment: '#token=tok222' },
    ], 'abc');
  });

  it('redirects new user to an available route with token', async () => {
    const res = await request(server, { path: '/abc' });
    assert.equal(res.status, 302);
    assert.ok(res.headers.location.startsWith('https://claw-abc-'));
    assert.ok(res.headers.location.includes('#token=tok'));
    assert.ok(res.headers['set-cookie'][0].includes('rlb_session='));
  });

  it('redirects returning user to their assigned route', async () => {
    const res1 = await request(server, { path: '/abc' });
    const cookie = res1.headers['set-cookie'][0].split(';')[0];

    const res2 = await request(server, { path: '/abc', headers: { cookie } });
    assert.equal(res2.status, 302);
    assert.equal(res2.headers.location, res1.headers.location);
  });

  it('returns 503 when all routes are assigned', async () => {
    await request(server, { path: '/abc' });
    await request(server, { path: '/abc' });
    const res = await request(server, { path: '/abc' });
    assert.equal(res.status, 503);
    assert.ok(res.body.includes('All seats are taken'));
  });

  it('treats stale cookie as new user', async () => {
    const res = await request(server, {
      path: '/abc',
      headers: { cookie: 'rlb_session=stale-value-from-previous-audience' },
    });
    assert.equal(res.status, 302);
    assert.ok(res.headers['set-cookie'][0].includes('rlb_session='));
  });

  it('returns 404 for wrong audience code', async () => {
    const res = await request(server, { path: '/wrongcode' });
    assert.equal(res.status, 404);
    assert.ok(res.body.includes('Session not found'));
  });

  it('returns 404 for expired code after reset', async () => {
    // Assign with code 'abc'
    await request(server, { path: '/abc' });

    // Reset with new audience
    db.loadRoutes([
      { public_host: 'claw-xyz-111.yougetaclaw.com', backend_host: 'claw-xyz-111.apps.ocp.example.com', enabled: true, token_fragment: '#token=xyz111' },
    ], 'xyz');

    // Old code no longer works
    const res = await request(server, { path: '/abc' });
    assert.equal(res.status, 404);
    assert.ok(res.body.includes('Session not found'));

    // New code works
    const res2 = await request(server, { path: '/xyz' });
    assert.equal(res2.status, 302);
  });

  it('returns 404 when no audience is loaded', async () => {
    const emptyDb = createDb(':memory:');
    const emptyApp = createApp({ db: emptyDb, cookieDomain: 'yougetaclaw.com' });
    const emptyServer = emptyApp.listen(0);
    await new Promise((r) => emptyServer.on('listening', r));

    const res = await request(emptyServer, { path: '/anycode' });
    assert.equal(res.status, 404);
    assert.ok(res.body.includes('Session not found'));

    emptyServer.close();
    emptyDb.close();
  });

  afterEach(() => {
    server.close();
    db.close();
  });
});

describe('rate limiting (when enabled)', () => {
  let db, app, server;

  beforeEach(async () => {
    db = createDb(':memory:');
    db.loadRoutes([
      { public_host: 'claw-abc-001.yougetaclaw.com', backend_host: 'claw-abc-001.apps.ocp.example.com', enabled: true, token_fragment: '#token=t001' },
      { public_host: 'claw-abc-002.yougetaclaw.com', backend_host: 'claw-abc-002.apps.ocp.example.com', enabled: true, token_fragment: '#token=t002' },
      { public_host: 'claw-abc-003.yougetaclaw.com', backend_host: 'claw-abc-003.apps.ocp.example.com', enabled: true, token_fragment: '#token=t003' },
      { public_host: 'claw-abc-004.yougetaclaw.com', backend_host: 'claw-abc-004.apps.ocp.example.com', enabled: true, token_fragment: '#token=t004' },
      { public_host: 'claw-abc-005.yougetaclaw.com', backend_host: 'claw-abc-005.apps.ocp.example.com', enabled: true, token_fragment: '#token=t005' },
    ], 'abc');
    app = createApp({ db, cookieDomain: 'yougetaclaw.com', rateLimit: { max: 3, windowMs: 60000 } });
    server = app.listen(0);
    await new Promise((r) => server.on('listening', r));
  });

  it('blocks after max new-user requests from the same IP', async () => {
    await request(server, { path: '/abc' });
    await request(server, { path: '/abc' });
    await request(server, { path: '/abc' });
    const res = await request(server, { path: '/abc' });
    assert.equal(res.status, 429);
    assert.ok(res.body.includes('Slow down'));
  });

  it('does not count returning users against the limit', async () => {
    const res1 = await request(server, { path: '/abc', headers: { 'x-forwarded-for': '1.1.1.1' } });
    const cookie = res1.headers['set-cookie'][0].split(';')[0];

    // Returning user visits should be skipped
    await request(server, { path: '/abc', headers: { cookie, 'x-forwarded-for': '1.1.1.1' } });
    await request(server, { path: '/abc', headers: { cookie, 'x-forwarded-for': '1.1.1.1' } });
    await request(server, { path: '/abc', headers: { cookie, 'x-forwarded-for': '1.1.1.1' } });

    // Another new user from a different IP should still be allowed
    const res2 = await request(server, { path: '/abc', headers: { 'x-forwarded-for': '2.2.2.2' } });
    assert.equal(res2.status, 302);
  });

  afterEach(() => {
    server.close();
    db.close();
  });
});

describe('rate limiting (when disabled)', () => {
  let db, app, server;

  beforeEach(async () => {
    db = createDb(':memory:');
    db.loadRoutes([
      { public_host: 'claw-abc-001.yougetaclaw.com', backend_host: 'claw-abc-001.apps.ocp.example.com', enabled: true, token_fragment: '#token=t001' },
      { public_host: 'claw-abc-002.yougetaclaw.com', backend_host: 'claw-abc-002.apps.ocp.example.com', enabled: true, token_fragment: '#token=t002' },
      { public_host: 'claw-abc-003.yougetaclaw.com', backend_host: 'claw-abc-003.apps.ocp.example.com', enabled: true, token_fragment: '#token=t003' },
      { public_host: 'claw-abc-004.yougetaclaw.com', backend_host: 'claw-abc-004.apps.ocp.example.com', enabled: true, token_fragment: '#token=t004' },
      { public_host: 'claw-abc-005.yougetaclaw.com', backend_host: 'claw-abc-005.apps.ocp.example.com', enabled: true, token_fragment: '#token=t005' },
    ], 'abc');
    app = createApp({ db, cookieDomain: 'yougetaclaw.com' });
    server = app.listen(0);
    await new Promise((r) => server.on('listening', r));
  });

  it('allows unlimited requests when rate limiting is off', async () => {
    await request(server, { path: '/abc' });
    await request(server, { path: '/abc' });
    await request(server, { path: '/abc' });
    const res = await request(server, { path: '/abc' });
    // 4th request gets through (no rate limit), but all routes may be assigned
    assert.ok(res.status === 302 || res.status === 503);
    assert.notEqual(res.status, 429);
  });

  afterEach(() => {
    server.close();
    db.close();
  });
});

describe('GET / (landing page)', () => {
  let db, app, server;

  beforeEach(async () => {
    db = createDb(':memory:');
    db.loadRoutes([
      { public_host: 'claw-abc-111.yougetaclaw.com', backend_host: 'claw-abc-111.apps.ocp.example.com', enabled: true, token_fragment: '#token=tok111' },
    ], 'abc');
    app = createApp({ db, cookieDomain: 'yougetaclaw.com' });
    server = app.listen(0);
    await new Promise((r) => server.on('listening', r));
  });

  it('shows landing page for new visitor', async () => {
    const res = await request(server, { path: '/' });
    assert.equal(res.status, 200);
    assert.ok(res.headers['content-type'].includes('text/html'));
    assert.ok(res.body.includes('Scan the QR code'));
  });

  it('redirects returning user with valid cookie (includes token)', async () => {
    // Get assigned first
    const res1 = await request(server, { path: '/abc' });
    const cookie = res1.headers['set-cookie'][0].split(';')[0];

    // Visit landing page with cookie — should redirect with token
    const res2 = await request(server, { path: '/', headers: { cookie } });
    assert.equal(res2.status, 302);
    assert.equal(res2.headers.location, res1.headers.location);
    assert.ok(res2.headers.location.includes('#token='));
  });

  it('shows landing page for stale cookie', async () => {
    const res = await request(server, {
      path: '/',
      headers: { cookie: 'rlb_session=stale-value' },
    });
    assert.equal(res.status, 200);
    assert.ok(res.body.includes('Scan the QR code'));
  });

  afterEach(() => {
    server.close();
    db.close();
  });
});
