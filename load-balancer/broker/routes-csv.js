'use strict';

const HOSTNAME_RE = /^[a-z0-9.-]+$/;

function parseRoutesCsv(text) {
  const routes = [];

  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;

    const parts = line.split(',');
    if (parts.length < 3) continue;

    const public_host = parts[0].trim().toLowerCase();
    const backend_host = parts[1].trim().toLowerCase();
    const enabled = parts[2].trim().toLowerCase() === 'true';

    if (!HOSTNAME_RE.test(public_host) || !HOSTNAME_RE.test(backend_host)) continue;

    routes.push({ public_host, backend_host, enabled });
  }

  return routes.filter(r => r.enabled);
}

module.exports = { parseRoutesCsv };
