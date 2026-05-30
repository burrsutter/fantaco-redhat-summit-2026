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

function createApp({ db, cookieDomain, routesCsvPath, statusKey, rateLimit: rateLimitOpts }) {
  const app = express();

  // Trust exactly 2 proxies (ALB + HAProxy) for accurate client IP
  app.set('trust proxy', 2);

  app.use(cookieParser());
  app.use(express.json());

  // Landing page — returning users get redirected, everyone else sees "scan QR code"
  app.get('/', (req, res) => {
    const existingCookie = req.cookies.rlb_session;
    if (existingCookie) {
      const assignment = db.findAssignment(existingCookie);
      if (assignment) {
        return res.redirect(302, `https://${assignment.public_host}${assignment.token_fragment || ''}`);
      }
    }
    res.type('html').send(LANDING_HTML);
  });

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
  app.get('/status/api', (req, res) => {
    const stats = db.getStats();
    const routes = db.getRoutesWithStatus().map(r => {
      // Extract cluster GUID from backend_host: *.apps.ocp.<guid>.sandbox*.opentlc.com
      const clusterMatch = r.backend_host.match(/\.apps\.ocp\.([^.]+)\./);
      return {
        ...r,
        cluster: clusterMatch ? clusterMatch[1] : '—',
        // Obscure backend host — show prefix, mask the cluster domain
        backend_host: r.backend_host.replace(/^([^.]+)\.(.+)$/, '$1.••••••'),
      };
    });
    res.json({ stats, routes });
  });

  // Block admin endpoints from external traffic (ALB/HAProxy adds X-Forwarded-For)
  app.use('/admin', (req, res, next) => {
    if (req.headers['x-forwarded-for']) {
      return res.status(403).json({ error: 'admin access denied' });
    }
    next();
  });

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

  // Optional rate limiting on assignment (enabled via RATE_LIMIT_ENABLED=true)
  const assignLimiter = rateLimitOpts
    ? createRateLimit({
        windowMs: rateLimitOpts.windowMs,
        max: rateLimitOpts.max,
        standardHeaders: true,
        legacyHeaders: false,
        handler: (_req, res) => res.status(429).type('html').send(RATE_LIMIT_HTML),
        skip: (req) => {
          const cookie = req.cookies.rlb_session;
          return cookie && db.findAssignment(cookie) !== null;
        },
      })
    : null;

  // Session assignment — requires valid audience code in URL
  app.get('/:code', ...(assignLimiter ? [assignLimiter] : []), (req, res) => {
    const { code } = req.params;

    // Validate code against current audience
    const stats = db.getStats();
    if (!stats.audience_id || stats.audience_id !== code) {
      return res.status(404).type('html').send(INVALID_CODE_HTML);
    }

    // Check for returning user
    const existingCookie = req.cookies.rlb_session;
    if (existingCookie) {
      const assignment = db.findAssignment(existingCookie);
      if (assignment) {
        return res.redirect(302, `https://${assignment.public_host}${assignment.token_fragment || ''}`);
      }
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

    return res.redirect(302, `https://${route.public_host}${route.token_fragment || ''}`);
  });

  return app;
}

module.exports = { createApp };
