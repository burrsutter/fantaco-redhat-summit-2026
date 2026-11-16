'use strict';

const express = require('express');
const cookieParser = require('cookie-parser');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const { parseRoutesCsv } = require('./routes-csv');
const createRateLimit = require('express-rate-limit').rateLimit;

const FULL_HOUSE_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'full-house.html'),
  'utf8'
);

const STATUS_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'status.html'),
  'utf8'
);

const LANDING_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'landing.html'),
  'utf8'
);

const INVALID_CODE_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'invalid-code.html'),
  'utf8'
);

const RATE_LIMIT_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'rate-limit.html'),
  'utf8'
);

function createApp({ db, cookieDomain, trustProxy, routesCsvPath, statusKey, rateLimit: rateLimitOpts }) {
  const app = express();
  const asyncRoute = (handler) => (req, res, next) =>
    Promise.resolve(handler(req, res)).catch(next);

  app.set('trust proxy', trustProxy != null ? trustProxy : 2);

  app.use(cookieParser());
  app.use(express.json());

  // Landing page — returning users get redirected, everyone else sees "scan QR code"
  app.get('/', asyncRoute(async (req, res) => {
    const existingCookie = req.cookies.rlb_session;
    if (existingCookie) {
      const assignment = await db.findAssignment(existingCookie);
      if (assignment) {
        return res.redirect(302, `https://${assignment.public_host}${assignment.token_fragment || ''}`);
      }
    }
    res.type('html').send(LANDING_HTML);
  }));

  // Protect status board with presenter key (when configured)
  app.use('/status', (req, res, next) => {
    if (statusKey && req.query.key !== statusKey) {
      return res.status(403).type('html').send(INVALID_CODE_HTML);
    }
    next();
  });

  // Status board — HTML page
  app.get('/status', (req, res) => {
    res.type('html').send(STATUS_HTML);
  });

  // Status board — JSON API
  app.get('/status/api', asyncRoute(async (req, res) => {
    const stats = await db.getStats();
    const routes = (await db.getRoutesWithStatus()).map(r => {
      // OpenShift route hosts commonly include apps.<platform>.<cluster>.
      const clusterMatch = r.backend_host.match(/\.apps\.[^.]+\.([^.]+)\./);
      return {
        ...r,
        cluster: clusterMatch ? clusterMatch[1] : '—',
        // Obscure backend host — show prefix, mask the cluster domain
        backend_host: r.backend_host.replace(/^([^.]+)\.(.+)$/, '$1.••••••'),
      };
    });
    res.json({ stats, routes });
  }));

  // Block admin endpoints from external traffic (ALB/HAProxy adds X-Forwarded-For)
  app.use('/admin', (req, res, next) => {
    if (req.headers['x-forwarded-for']) {
      return res.status(403).json({ error: 'admin access denied' });
    }
    next();
  });

  // Admin: reset all assignments and reload routes from CSV
  app.post('/admin/reset', asyncRoute(async (req, res) => {
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

    await db.loadRoutes(routes, audienceId);
    const stats = await db.getStats();
    res.json({ ok: true, ...stats });
  }));

  // Admin: reload routes from CSV without wiping assignments
  // Use this for single-user resets — only the changed route loses its assignment
  app.post('/admin/reload', asyncRoute(async (req, res) => {
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

    await db.reloadRoutes(routes);
    const stats = await db.getStats();
    res.json({ ok: true, ...stats });
  }));

  // Admin: release a single assignment
  app.post('/admin/release/:slot', asyncRoute(async (req, res) => {
    // PostgreSQL BIGINT values are returned as strings by node-postgres.
    const routeId = req.params.slot;
    if (!/^\d+$/.test(routeId)) {
      return res.status(400).json({ error: 'invalid route id' });
    }
    const routes = await db.getAllRoutes();
    const route = routes.find((r) => String(r.id) === routeId);
    if (!route) {
      return res.status(404).json({ error: 'route not found' });
    }
    await db.releaseRoute(routeId);
    res.json({ ok: true, released: route.public_host });
  }));

  // Optional rate limiting on assignment (enabled via RATE_LIMIT_ENABLED=true)
  const assignLimiter = rateLimitOpts
    ? createRateLimit({
        windowMs: rateLimitOpts.windowMs,
        max: rateLimitOpts.max,
        standardHeaders: true,
        legacyHeaders: false,
        handler: (_req, res) => res.status(429).type('html').send(RATE_LIMIT_HTML),
        skip: async (req) => {
          const cookie = req.cookies.rlb_session;
          return cookie && await db.findAssignment(cookie) !== null;
        },
      })
    : null;

  // Session assignment — requires valid audience code in URL
  app.get('/:code', ...(assignLimiter ? [assignLimiter] : []), asyncRoute(async (req, res) => {
    const { code } = req.params;

    // Validate code against current audience
    const stats = await db.getStats();
    if (!stats.audience_id || stats.audience_id !== code) {
      return res.status(404).type('html').send(INVALID_CODE_HTML);
    }

    // Check for returning user
    const existingCookie = req.cookies.rlb_session;
    if (existingCookie) {
      const assignment = await db.findAssignment(existingCookie);
      if (assignment) {
        return res.redirect(302, `https://${assignment.public_host}${assignment.token_fragment || ''}`);
      }
    }

    // New user (or stale cookie) — assign a route
    const cookieValue = uuidv4();
    const route = await db.assignRoute(cookieValue);

    if (!route) {
      return res.status(503).send(FULL_HOUSE_HTML);
    }

    const cookieOpts = {
      path: '/',
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
      maxAge: 86400 * 1000,
    };
    if (cookieDomain) cookieOpts.domain = cookieDomain;
    res.cookie('rlb_session', cookieValue, cookieOpts);

    return res.redirect(302, `https://${route.public_host}${route.token_fragment || ''}`);
  }));

  app.get('/health/ready', asyncRoute(async (_req, res) => {
    await db.getStats();
    res.status(200).send('ok');
  }));

  return app;
}

module.exports = { createApp };
