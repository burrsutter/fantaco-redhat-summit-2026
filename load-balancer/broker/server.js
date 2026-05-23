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
