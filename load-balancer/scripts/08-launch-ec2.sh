#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

# --- Read state from previous scripts ---
HAPROXY_SG_ID=$(cat "$STATE_DIR/haproxy-sg-id" 2>/dev/null || true)
INSTANCE_PROFILE_ARN=$(cat "$STATE_DIR/instance-profile-arn" 2>/dev/null || true)
VPC_ID=$(cat "$STATE_DIR/vpc-id" 2>/dev/null || true)

if [[ -z "$HAPROXY_SG_ID" ]]; then
  echo "ERROR: No haproxy-sg-id found. Run 06-create-security-groups.sh first." >&2
  exit 1
fi
if [[ -z "$INSTANCE_PROFILE_ARN" ]]; then
  echo "ERROR: No instance-profile-arn found. Run 07-create-iam-role.sh first." >&2
  exit 1
fi
if [[ -z "$VPC_ID" ]]; then
  echo "ERROR: No vpc-id found. Run 06-create-security-groups.sh first." >&2
  exit 1
fi

# --- Check idempotency ---
echo "==> Checking for existing route-lb-haproxy instance"
EXISTING_ID=$(aws ec2 describe-instances \
  --filters \
    Name=tag:Name,Values=route-lb-haproxy \
    Name=instance-state-name,Values=running,pending \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [[ -n "$EXISTING_ID" && "$EXISTING_ID" != "None" ]]; then
  echo "Instance already exists: $EXISTING_ID"
  echo "$EXISTING_ID" > "$STATE_DIR/ec2-instance-id"
  exit 0
fi

# --- Discover AMI ---
echo "==> Discovering latest Amazon Linux 2023 AMI"
ARCH="x86_64"
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters \
    Name=name,Values="al2023-ami-2023*-kernel-*-${ARCH}" \
    Name=state,Values=available \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
  echo "ERROR: Could not find Amazon Linux 2023 AMI." >&2
  exit 1
fi
echo "Using AMI: $AMI_ID"

# --- Discover public subnet ---
echo "==> Discovering public subnet in default VPC"
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text)

if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
  echo "ERROR: No public subnet found in VPC $VPC_ID." >&2
  exit 1
fi
echo "Using subnet: $SUBNET_ID"

# --- Generate user-data ---
echo "==> Generating user-data script"
USERDATA=$(cat <<'USERDATA_SCRIPT'
#!/bin/bash
set -euxo pipefail

# --- Install packages ---
dnf install -y haproxy awscli2 jq socat nodejs22

# --- HAProxy config ---
cat > /etc/haproxy/haproxy.cfg <<'HAPCFG'
global
    log stdout format raw local0
    maxconn 4096

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    timeout tunnel  1h

frontend http_in
    bind *:__HAPROXY_PORT__

    # Bare domain goes to session broker
    acl is_bare_domain hdr(host) -i __DOMAIN__
    use_backend broker if is_bare_domain

    use_backend %[req.hdr(host),lower,map_str(/etc/haproxy/routes.map)]
    default_backend bk_default

backend bk_default
    http-request return status 503 content-type text/plain string "no route configured for this host"

backend broker
    server broker 127.0.0.1:3000

listen health
    bind *:8081
    http-request return status 200 content-type text/plain string "ready"
HAPCFG

sed -i "s/__HAPROXY_PORT__/__PORT__/g" /etc/haproxy/haproxy.cfg

# --- Empty map file ---
touch /etc/haproxy/routes.map

# --- Sync script ---
mkdir -p /usr/local/bin
cat > /usr/local/bin/route-lb-sync <<'SYNC'
#!/bin/bash
set -euo pipefail

source /etc/route-lb/env

TMPCSV=$(mktemp)
trap 'rm -f "$TMPCSV"' EXIT

aws s3 cp "s3://${CONFIG_BUCKET}/${ROUTE_CATALOG_KEY}" "$TMPCSV"

TMPMAP=$(mktemp)
trap 'rm -f "$TMPCSV" "$TMPMAP"' EXIT

while IFS=, read -r public_host openshift_route_host enabled; do
  # skip header and comments
  [[ "$public_host" =~ ^#.* ]] && continue
  [[ "$public_host" == "public_host" ]] && continue
  [[ "$enabled" != "true" ]] && continue
  echo "${public_host} bk_${public_host//[^a-zA-Z0-9]/_}" >> "$TMPMAP"
done < "$TMPCSV"

# Build backend configs
BACKENDS=""
while IFS=, read -r public_host openshift_route_host enabled; do
  [[ "$public_host" =~ ^#.* ]] && continue
  [[ "$public_host" == "public_host" ]] && continue
  [[ "$enabled" != "true" ]] && continue
  BK_NAME="bk_${public_host//[^a-zA-Z0-9]/_}"
  BACKENDS+="
backend ${BK_NAME}
    http-request set-header Host ${openshift_route_host}
    server s1 ${OPENSHIFT_ROUTER_DNS}:443 ssl verify none sni str(${openshift_route_host})
"
done < "$TMPCSV"

# Atomically update map
cp "$TMPMAP" /etc/haproxy/routes.map.new
mv /etc/haproxy/routes.map.new /etc/haproxy/routes.map

# Rebuild haproxy config with backends
# Keep everything up to and including the health listen block, then append backends
awk '/^listen health/,0' /etc/haproxy/haproxy.cfg > /dev/null 2>&1
BASECFG=$(sed '/^backend bk_/,$d' /etc/haproxy/haproxy.cfg | sed '/^$/N;/^\n$/d')
{
  echo "$BASECFG"
  echo "$BACKENDS"
} > /etc/haproxy/haproxy.cfg.new
mv /etc/haproxy/haproxy.cfg.new /etc/haproxy/haproxy.cfg

# Reload HAProxy
systemctl reload haproxy || systemctl restart haproxy
echo "route-lb-sync complete: $(wc -l < /etc/haproxy/routes.map) routes"
SYNC
chmod +x /usr/local/bin/route-lb-sync

# --- Environment file ---
mkdir -p /etc/route-lb
cat > /etc/route-lb/env <<ENVFILE
CONFIG_BUCKET=__CONFIG_BUCKET__
ROUTE_CATALOG_KEY=__ROUTE_CATALOG_KEY__
OPENSHIFT_ROUTER_DNS=__OPENSHIFT_ROUTER_DNS__
AWS_REGION=__AWS_REGION__
ENVFILE

# --- Systemd service + timer ---
cat > /etc/systemd/system/route-lb-sync.service <<'SVC'
[Unit]
Description=Sync route-lb routes from S3
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/route-lb/env
ExecStart=/usr/local/bin/route-lb-sync
SVC

cat > /etc/systemd/system/route-lb-sync.timer <<'TMR'
[Unit]
Description=Periodic route-lb sync

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s

[Install]
WantedBy=timers.target
TMR

systemctl daemon-reload
systemctl enable --now haproxy
systemctl enable --now route-lb-sync.timer

# --- First sync ---
/usr/local/bin/route-lb-sync || true

# --- Install broker ---
mkdir -p /opt/route-lb-broker/pages /var/lib/route-lb

cat > /opt/route-lb-broker/package.json <<'BROKER_PKG'
{
  "name": "route-lb-broker",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node server.js",
    "test": "node --test test/*.test.js"
  },
  "dependencies": {
    "better-sqlite3": "^11.0.0",
    "cookie-parser": "^1.4.7",
    "express": "^4.21.0",
    "uuid": "^11.0.0"
  }
}
BROKER_PKG

cat > /opt/route-lb-broker/routes-csv.js <<'BROKER_CSV'
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
BROKER_CSV

cat > /opt/route-lb-broker/db.js <<'BROKER_DB'
'use strict';
const Database = require('better-sqlite3');
function createDb(dbPath) {
  const sqlite = new Database(dbPath);
  sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('foreign_keys = ON');
  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS routes (
      id INTEGER PRIMARY KEY AUTOINCREMENT, public_host TEXT NOT NULL UNIQUE,
      backend_host TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1);
    CREATE TABLE IF NOT EXISTS assignments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, cookie_value TEXT NOT NULL UNIQUE,
      route_id INTEGER NOT NULL REFERENCES routes(id),
      assigned_at TEXT NOT NULL DEFAULT (datetime('now')));
    CREATE TABLE IF NOT EXISTS audiences (
      id INTEGER PRIMARY KEY AUTOINCREMENT, audience_id TEXT,
      started_at TEXT NOT NULL DEFAULT (datetime('now')), active INTEGER NOT NULL DEFAULT 1);
  `);
  const stmts = {
    insertRoute: sqlite.prepare('INSERT INTO routes (public_host, backend_host, enabled) VALUES (?, ?, ?)'),
    deleteAllRoutes: sqlite.prepare('DELETE FROM routes'),
    deleteAllAssignments: sqlite.prepare('DELETE FROM assignments'),
    deactivateAudiences: sqlite.prepare('UPDATE audiences SET active = 0'),
    insertAudience: sqlite.prepare('INSERT INTO audiences (audience_id, active) VALUES (?, 1)'),
    findAvailable: sqlite.prepare('SELECT r.id, r.public_host, r.backend_host FROM routes r LEFT JOIN assignments a ON a.route_id = r.id WHERE r.enabled = 1 AND a.id IS NULL ORDER BY r.id LIMIT 1'),
    insertAssignment: sqlite.prepare('INSERT INTO assignments (cookie_value, route_id) VALUES (?, ?)'),
    findByCookie: sqlite.prepare('SELECT r.id, r.public_host, r.backend_host FROM assignments a JOIN routes r ON r.id = a.route_id WHERE a.cookie_value = ?'),
    releaseByRouteId: sqlite.prepare('DELETE FROM assignments WHERE route_id = ?'),
    allRoutes: sqlite.prepare('SELECT * FROM routes ORDER BY id'),
    routesWithStatus: sqlite.prepare('SELECT r.id, r.public_host, r.backend_host, r.enabled, CASE WHEN a.id IS NOT NULL THEN 1 ELSE 0 END as assigned, a.assigned_at FROM routes r LEFT JOIN assignments a ON a.route_id = r.id ORDER BY r.id'),
    countTotal: sqlite.prepare('SELECT COUNT(*) as n FROM routes WHERE enabled = 1'),
    countAssigned: sqlite.prepare('SELECT COUNT(*) as n FROM assignments a JOIN routes r ON r.id = a.route_id WHERE r.enabled = 1'),
    activeAudience: sqlite.prepare('SELECT audience_id, started_at FROM audiences WHERE active = 1 ORDER BY id DESC LIMIT 1'),
  };
  const loadRoutes = sqlite.transaction((routes, audienceId) => {
    stmts.deleteAllAssignments.run(); stmts.deleteAllRoutes.run(); stmts.deactivateAudiences.run();
    for (const r of routes) stmts.insertRoute.run(r.public_host, r.backend_host, r.enabled ? 1 : 0);
    if (audienceId) stmts.insertAudience.run(audienceId);
  });
  return {
    loadRoutes,
    assignRoute(cookieValue) { const route = stmts.findAvailable.get(); if (!route) return null; stmts.insertAssignment.run(cookieValue, route.id); return route; },
    findAssignment(cookieValue) { return stmts.findByCookie.get(cookieValue) || null; },
    releaseRoute(routeId) { stmts.releaseByRouteId.run(routeId); },
    resetAssignments() { stmts.deleteAllAssignments.run(); },
    getAllRoutes() { return stmts.allRoutes.all(); },
    getRoutesWithStatus() { return stmts.routesWithStatus.all(); },
    getStats() { const total = stmts.countTotal.get().n; const assigned = stmts.countAssigned.get().n; const audience = stmts.activeAudience.get(); return { total, assigned, available: total - assigned, audience_id: audience ? audience.audience_id : null, audience_started: audience ? audience.started_at : null }; },
    close() { sqlite.close(); },
  };
}
module.exports = { createDb };
BROKER_DB

cat > /opt/route-lb-broker/app.js <<'BROKER_APP'
'use strict';
const express = require('express');
const cookieParser = require('cookie-parser');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const { parseRoutesCsv } = require('./routes-csv');
const FULL_HOUSE_HTML = fs.readFileSync(path.join(__dirname, 'pages', 'full-house.html'), 'utf8');
const STATUS_HTML = fs.readFileSync(path.join(__dirname, 'pages', 'status.html'), 'utf8');
function createApp({ db, cookieDomain, routesCsvPath }) {
  const app = express();
  app.use(cookieParser());
  app.use(express.json());
  app.get('/', (req, res) => {
    const existingCookie = req.cookies.rlb_session;
    if (existingCookie) { const assignment = db.findAssignment(existingCookie); if (assignment) return res.redirect(302, `https://${assignment.public_host}`); }
    const cookieValue = uuidv4();
    const route = db.assignRoute(cookieValue);
    if (!route) return res.status(503).send(FULL_HOUSE_HTML);
    res.cookie('rlb_session', cookieValue, { domain: cookieDomain, path: '/', httpOnly: true, secure: true, sameSite: 'lax', maxAge: 86400 * 1000 });
    return res.redirect(302, `https://${route.public_host}`);
  });
  app.get('/status', (req, res) => { res.type('html').send(STATUS_HTML); });
  app.get('/status/api', (req, res) => { const stats = db.getStats(); const routes = db.getRoutesWithStatus(); res.json({ stats, routes }); });
  app.post('/admin/reset', (req, res) => {
    if (!routesCsvPath) return res.status(500).json({ error: 'no routesCsvPath configured' });
    let csvText; try { csvText = fs.readFileSync(routesCsvPath, 'utf8'); } catch (err) { return res.status(500).json({ error: `failed to read ${routesCsvPath}: ${err.message}` }); }
    const routes = parseRoutesCsv(csvText);
    if (routes.length === 0) return res.status(400).json({ error: 'no enabled routes found in CSV' });
    const match = routes[0].public_host.match(/^claw-([a-z0-9]+)-/);
    const audienceId = match ? match[1] : null;
    db.loadRoutes(routes, audienceId);
    const stats = db.getStats();
    res.json({ ok: true, ...stats });
  });
  app.post('/admin/release/:slot', (req, res) => {
    const routeId = parseInt(req.params.slot, 10);
    const routes = db.getAllRoutes();
    const route = routes.find((r) => r.id === routeId);
    if (!route) return res.status(404).json({ error: 'route not found' });
    db.releaseRoute(routeId);
    res.json({ ok: true, released: route.public_host });
  });
  return app;
}
module.exports = { createApp };
BROKER_APP

cat > /opt/route-lb-broker/server.js <<'BROKER_SERVER'
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
const existingRoutes = db.getAllRoutes();
if (existingRoutes.length === 0) {
  try { const csvText = fs.readFileSync(ROUTES_CSV_PATH, 'utf8'); const routes = parseRoutesCsv(csvText);
    if (routes.length > 0) { const match = routes[0].public_host.match(/^claw-([a-z0-9]+)-/); const audienceId = match ? match[1] : null; db.loadRoutes(routes, audienceId); console.log(`Loaded ${routes.length} routes from ${ROUTES_CSV_PATH} (audience: ${audienceId})`); }
  } catch (err) { console.log(`No routes loaded on startup: ${err.message}`); }
}
const app = createApp({ db, cookieDomain: COOKIE_DOMAIN, routesCsvPath: ROUTES_CSV_PATH });
const server = app.listen(PORT, () => { const stats = db.getStats(); console.log(`Route-LB broker listening on :${PORT}`); console.log(`  Routes: ${stats.total} (${stats.assigned} assigned, ${stats.available} available)`); console.log(`  Audience: ${stats.audience_id || 'none'}`); });
process.on('SIGTERM', () => { server.close(() => { db.close(); process.exit(0); }); });
process.on('SIGINT', () => { server.close(() => { db.close(); process.exit(0); }); });
BROKER_SERVER

cat > /opt/route-lb-broker/pages/full-house.html <<'BROKER_FULLHOUSE'
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>You Get a Claw</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0a0a1a;color:#e0e0e0;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px}.card{text-align:center;max-width:480px}h1{font-size:2rem;margin-bottom:12px;color:#ff6b6b}p{font-size:1.1rem;line-height:1.6;color:#aaa}</style>
</head><body><div class="card"><h1>All seats are taken</h1><p>All seats are taken for this session.<br>Please check with the presenter.</p></div></body></html>
BROKER_FULLHOUSE

cat > /opt/route-lb-broker/pages/status.html <<'BROKER_STATUS'
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Route-LB Status</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0a0a1a;color:#e0e0e0;padding:24px;max-width:1200px;margin:0 auto}header{display:flex;justify-content:space-between;align-items:center;margin-bottom:24px;flex-wrap:wrap;gap:16px}h1{font-size:1.5rem}.audience{color:#888;font-size:.9rem}.audience code{color:#64ffda}.counters{display:flex;gap:32px;text-align:center}.counter-value{font-size:2.5rem;font-weight:bold;line-height:1}.counter-label{font-size:.7rem;color:#888;text-transform:uppercase;letter-spacing:1px;margin-top:4px}.assigned-color{color:#64ffda}.available-color{color:#ffd93d}table{width:100%;border-collapse:collapse;font-size:.85rem}th{text-align:left;padding:8px;color:#888;border-bottom:1px solid #333;font-weight:normal}td{padding:8px;border-bottom:1px solid #1a1a2e;font-family:'SF Mono',Consolas,monospace;font-size:.8rem}.status-assigned{color:#64ffda}.status-available{color:#ffd93d}.refresh-note{margin-top:16px;color:#555;font-size:.75rem}.no-routes{text-align:center;padding:48px;color:#555}</style>
</head><body>
<header><div><h1>Route-LB Status</h1><div class="audience">Audience: <code id="audience-id">—</code> · Started <span id="audience-started">—</span></div></div>
<div class="counters"><div><div class="counter-value assigned-color" id="count-assigned">—</div><div class="counter-label">Assigned</div></div><div><div class="counter-value available-color" id="count-available">—</div><div class="counter-label">Available</div></div></div></header>
<table><thead><tr><th>#</th><th>Public Host</th><th>Backend Route</th><th>Status</th><th>Assigned At</th></tr></thead><tbody id="route-table"></tbody></table>
<div class="refresh-note">Auto-refreshes every 5 seconds</div>
<script>
async function refresh(){try{const res=await fetch('/status/api');const data=await res.json();document.getElementById('audience-id').textContent=data.stats.audience_id||'—';document.getElementById('audience-started').textContent=data.stats.audience_started||'—';document.getElementById('count-assigned').textContent=data.stats.assigned;document.getElementById('count-available').textContent=data.stats.available;const tbody=document.getElementById('route-table');if(data.routes.length===0){tbody.innerHTML='<tr><td colspan="5" class="no-routes">No routes loaded</td></tr>';return;}tbody.innerHTML=data.routes.map((r,i)=>`<tr><td>${String(i+1).padStart(3,'0')}</td><td>${r.public_host}</td><td style="color:#666">${r.backend_host}</td><td class="${r.assigned?'status-assigned':'status-available'}">${r.assigned?'● assigned':'○ available'}</td><td style="color:#666">${r.assigned_at||'—'}</td></tr>`).join('');}catch(err){console.error('refresh failed:',err);}}
refresh();setInterval(refresh,5000);
</script></body></html>
BROKER_STATUS

cd /opt/route-lb-broker && npm install --production

# --- Broker systemd service ---
cat > /etc/systemd/system/route-lb-broker.service <<'BROKERSVC'
[Unit]
Description=Route-LB Session Broker
After=network-online.target haproxy.service

[Service]
Type=simple
WorkingDirectory=/opt/route-lb-broker
ExecStart=/usr/bin/node server.js
Restart=always
Environment=PORT=3000
Environment=DB_PATH=/var/lib/route-lb/broker.db
Environment=ROUTES_CSV_PATH=/var/lib/route-lb/routes.csv
Environment=COOKIE_DOMAIN=__DOMAIN__

[Install]
WantedBy=multi-user.target
BROKERSVC

systemctl daemon-reload
systemctl enable --now route-lb-broker

echo "route-lb-haproxy setup complete"
USERDATA_SCRIPT
)

# Substitute placeholders
USERDATA="${USERDATA//__PORT__/$HAPROXY_PORT}"
USERDATA="${USERDATA//__CONFIG_BUCKET__/$CONFIG_BUCKET}"
USERDATA="${USERDATA//__ROUTE_CATALOG_KEY__/$ROUTE_CATALOG_KEY}"
USERDATA="${USERDATA//__OPENSHIFT_ROUTER_DNS__/$OPENSHIFT_ROUTER_DNS}"
USERDATA="${USERDATA//__AWS_REGION__/$AWS_REGION}"
USERDATA="${USERDATA//__DOMAIN__/$DOMAIN}"

# --- Launch instance ---
echo "==> Launching EC2 instance"
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$HAPROXY_SG_ID" \
  --iam-instance-profile "Arn=$INSTANCE_PROFILE_ARN" \
  --associate-public-ip-address \
  --user-data "$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=route-lb-haproxy}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance launched: $INSTANCE_ID"
echo "$INSTANCE_ID" > "$STATE_DIR/ec2-instance-id"

echo "==> Waiting for instance to reach running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "Instance is running."

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo ""
echo "State files written:"
echo "  $STATE_DIR/ec2-instance-id = $INSTANCE_ID"
echo ""
echo "Instance details:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP:   $PUBLIC_IP"
echo ""
echo "Check user-data progress:"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo "  sudo tail -f /var/log/cloud-init-output.log"
