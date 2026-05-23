'use strict';

const express = require('express');
const cookieParser = require('cookie-parser');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');

const FULL_HOUSE_HTML = fs.readFileSync(
  path.join(__dirname, 'pages', 'full-house.html'),
  'utf8'
);

function createApp({ db, cookieDomain }) {
  const app = express();
  app.use(cookieParser());

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

  return app;
}

module.exports = { createApp };
