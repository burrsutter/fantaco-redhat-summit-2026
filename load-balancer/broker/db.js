'use strict';

const Database = require('better-sqlite3');

function createDb(dbPath) {
  const sqlite = new Database(dbPath);
  sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('foreign_keys = ON');

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS routes (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      public_host     TEXT NOT NULL UNIQUE,
      backend_host    TEXT NOT NULL,
      enabled         INTEGER NOT NULL DEFAULT 1,
      namespace       TEXT NOT NULL DEFAULT '',
      token_fragment  TEXT NOT NULL DEFAULT ''
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

  // Migration: add namespace column to existing databases
  try {
    sqlite.exec('ALTER TABLE routes ADD COLUMN namespace TEXT NOT NULL DEFAULT ""');
  } catch (_) { /* column already exists */ }

  // Migration: add token_fragment column to existing databases
  try {
    sqlite.exec('ALTER TABLE routes ADD COLUMN token_fragment TEXT NOT NULL DEFAULT ""');
  } catch (_) { /* column already exists */ }

  const stmts = {
    insertRoute: sqlite.prepare(
      'INSERT INTO routes (public_host, backend_host, enabled, namespace, token_fragment) VALUES (?, ?, ?, ?, ?)'
    ),
    deleteAllRoutes: sqlite.prepare('DELETE FROM routes'),
    deleteAllAssignments: sqlite.prepare('DELETE FROM assignments'),
    deactivateAudiences: sqlite.prepare('UPDATE audiences SET active = 0'),
    insertAudience: sqlite.prepare(
      'INSERT INTO audiences (audience_id, active) VALUES (?, 1)'
    ),
    findAvailable: sqlite.prepare(`
      SELECT r.id, r.public_host, r.backend_host, r.token_fragment FROM routes r
      LEFT JOIN assignments a ON a.route_id = r.id
      WHERE r.enabled = 1 AND a.id IS NULL
      ORDER BY r.id LIMIT 1
    `),
    insertAssignment: sqlite.prepare(
      'INSERT INTO assignments (cookie_value, route_id) VALUES (?, ?)'
    ),
    findByCookie: sqlite.prepare(`
      SELECT r.id, r.public_host, r.backend_host, r.token_fragment FROM assignments a
      JOIN routes r ON r.id = a.route_id
      WHERE a.cookie_value = ?
    `),
    releaseByRouteId: sqlite.prepare(
      'DELETE FROM assignments WHERE route_id = ?'
    ),
    allRoutes: sqlite.prepare('SELECT * FROM routes ORDER BY id'),
    routesWithStatus: sqlite.prepare(`
      SELECT r.id, r.public_host, r.backend_host, r.enabled, r.namespace, r.token_fragment,
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
      stmts.insertRoute.run(r.public_host, r.backend_host, r.enabled ? 1 : 0, r.namespace || '', r.token_fragment || '');
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
