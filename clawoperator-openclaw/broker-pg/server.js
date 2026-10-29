'use strict';

const fs = require('fs');
const { createDb } = require('./db');
const { createApp } = require('./app');
const { parseRoutesCsv } = require('./routes-csv');

const PORT = parseInt(process.env.PORT || '3000', 10);
const ROUTES_CSV_PATH = process.env.ROUTES_CSV_PATH || './routes.csv';
const COOKIE_DOMAIN = process.env.COOKIE_DOMAIN || '';
const TRUST_PROXY = process.env.TRUST_PROXY || '2';

const STATUS_KEY = process.env.BROKER_STATUS_KEY || process.env.STATUS_KEY || '';
const RATE_LIMIT_ENABLED = process.env.RATE_LIMIT_ENABLED === 'true';
const RATE_LIMIT_MAX = parseInt(process.env.RATE_LIMIT_MAX || '3', 10);
const RATE_LIMIT_WINDOW_MS = parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10);

async function start() {
  const db = await createDb();
  const existingRoutes = await db.getAllRoutes();
  if (existingRoutes.length === 0) {
    try {
      const csvText = fs.readFileSync(ROUTES_CSV_PATH, 'utf8');
      const routes = parseRoutesCsv(csvText);
      if (routes.length > 0) {
        const match = routes[0].public_host.match(/^claw-([a-z0-9]+)-/);
        const audienceId = match ? match[1] : null;
        await db.loadRoutes(routes, audienceId);
        console.log(`Loaded ${routes.length} routes from ${ROUTES_CSV_PATH} (audience: ${audienceId})`);
      }
    } catch (err) {
      console.log(`No routes loaded on startup: ${err.message}`);
    }
  }

  const app = createApp({
    db,
    cookieDomain: COOKIE_DOMAIN,
    trustProxy: /^\d+$/.test(TRUST_PROXY) ? parseInt(TRUST_PROXY, 10) : TRUST_PROXY,
    routesCsvPath: ROUTES_CSV_PATH,
    statusKey: STATUS_KEY,
    rateLimit: RATE_LIMIT_ENABLED ? { max: RATE_LIMIT_MAX, windowMs: RATE_LIMIT_WINDOW_MS } : null,
  });
  const server = app.listen(PORT, async () => {
    const stats = await db.getStats();
    console.log(`Route-LB broker listening on :${PORT}`);
    console.log(`  Routes: ${stats.total} (${stats.assigned} assigned, ${stats.available} available)`);
    console.log(`  Audience: ${stats.audience_id || 'none'}`);
  });

  const shutdown = () => {
    server.close(async () => {
      await db.close();
      process.exit(0);
    });
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

start().catch((error) => {
  console.error('Broker startup failed:', error.message);
  process.exit(1);
});
