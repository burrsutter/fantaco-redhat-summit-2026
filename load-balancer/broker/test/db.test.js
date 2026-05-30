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
        { public_host: 'a.example.com', backend_host: 'a.ocp.example.com', enabled: true, token_fragment: '#token=aaa111' },
        { public_host: 'b.example.com', backend_host: 'b.ocp.example.com', enabled: true, token_fragment: '#token=bbb222' },
      ], 'abc12');
    });

    it('assigns first available route', () => {
      const route = db.assignRoute('cookie-1');
      assert.equal(route.public_host, 'a.example.com');
    });

    it('includes token_fragment in assigned route', () => {
      const route = db.assignRoute('cookie-1');
      assert.equal(route.token_fragment, '#token=aaa111');
    });

    it('includes token_fragment in cookie lookup', () => {
      db.assignRoute('cookie-1');
      const found = db.findAssignment('cookie-1');
      assert.equal(found.token_fragment, '#token=aaa111');
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
