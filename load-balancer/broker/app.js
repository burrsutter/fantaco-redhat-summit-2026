'use strict';

const express = require('express');
const cookieParser = require('cookie-parser');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const { parseRoutesCsv } = require('./routes-csv');

const FULL_HOUSE_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'full-house.html'),
  'utf8'
);

function createApp({ db, cookieDomain, routesCsvPath }) {
  const app = express();
  app.use(cookieParser());
  app.use(express.json());

  // Session assignment
  app.get('/', (req, res) => {
    const existingCookie = req.cookies.rlb_session;

    // Check for returning user
    if (existingCookie) {
      const assignment = db.findAssignment(existingCookie);
      if (assignment) {
        return res.redirect(302, `https://${assignment.public_host}`);
      }
      // Stale cookie — fall through to assign a new route
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

    return res.redirect(302, `https://${route.public_host}`);
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

  return app;
}

module.exports = { createApp };
