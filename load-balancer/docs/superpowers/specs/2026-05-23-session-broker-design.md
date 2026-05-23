# Route-LB Session Broker Design

## Problem

OpenClaw Gateway instances run on OpenShift behind randomly generated Routes (`claw-{audience}-{user}.apps.ocp...`). For each presentation/audience session, the `audience-reset.sh` script destroys old instances and creates new ones with fresh random URLs.

Audience members need a single stable entry point (`https://yougetaclaw.com`) that assigns them to an exclusive OpenClaw Gateway instance and returns them to the same instance on subsequent visits within the same audience session.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| User identification | Browser cookie | No login required. First-party cookie on `yougetaclaw.com`. |
| Capacity model | One user per route, exclusive | Each audience member gets their own OpenClaw instance. |
| Assignment expiry | Admin manually releases (audience reset) | Presentation-driven lifecycle, not time-based. |
| Session broker location | HAProxy EC2 instance | Co-located, no extra infrastructure. |
| Routing mechanism | HTTP 302 redirect | Broker only handles initial assignment. After redirect, HAProxy map routes directly. |
| Public host pattern | Matches OpenShift Route | `claw-28c43-ef0ea4.yougetaclaw.com` mirrors `claw-28c43-ef0ea4.apps.ocp...`. Non-guessable. |
| Full house behavior | Branded 503 page | "All seats are taken for this session." |
| Admin UI | Read-only status board | Route management stays via CLI/S3. |
| Persistence | SQLite | Survives restarts, zero infrastructure. |

## Architecture

```
Audience member's phone
  → yougetaclaw.com (Route 53 wildcard DNS)
  → AWS ALB (TLS termination, ACM cert for *.yougetaclaw.com)
  → HAProxy on EC2 (:8080)
      ├── Host: yougetaclaw.com (bare domain)
      │     → Broker service (localhost:3000)
      │     → Check cookie, assign route, set cookie
      │     → 302 redirect → claw-28c43-ef0ea4.yougetaclaw.com
      │
      ├── Host: claw-28c43-ef0ea4.yougetaclaw.com (after redirect)
      │     → HAProxy map lookup
      │     → claw-28c43-ef0ea4.apps.ocp.nnsnv.sandbox571.opentlc.com
      │     → OpenClaw Gateway pod (WebSocket, chat UI)
      │
      └── Host: yougetaclaw.com/status
            → Broker service (localhost:3000)
            → Read-only status board HTML
```

### Components

| Component | What it does | Where it runs |
|---|---|---|
| HAProxy | Map-based host routing for `claw-*` URLs | EC2 :8080 |
| Broker (Node.js + Express) | Session assignment, cookie management, status board | EC2 :3000 |
| SQLite DB | Route pool and user assignments | EC2 `/var/lib/route-lb/broker.db` |
| `routes.csv` (S3) | Source of truth for route pool | S3 `yougetaclaw-route-lb-config` |
| `audience-reset.sh` | Reset OpenClaw instances, generate new routes | Admin laptop (oc CLI) |

### What is not in scope

- Queue or waitlist when all slots are full.
- Time-based assignment expiry.
- Password auto-fill or token passthrough to OpenClaw.
- Per-pod routing or OpenShift operator integration.
- Multi-instance HAProxy (Auto Scaling Group).
- Shared session store for cross-pod reconnection.

## Route Catalog (routes.csv)

After an audience reset, `routes.csv` maps the random public host to the matching OpenShift Route:

```csv
# public_host,openshift_route_host,enabled
claw-28c43-ef0ea4.yougetaclaw.com,claw-28c43-ef0ea4.apps.ocp.nnsnv.sandbox571.opentlc.com,true
claw-28c43-f19614.yougetaclaw.com,claw-28c43-f19614.apps.ocp.nnsnv.sandbox571.opentlc.com,true
claw-28c43-d59728.yougetaclaw.com,claw-28c43-d59728.apps.ocp.nnsnv.sandbox571.opentlc.com,true
claw-28c43-c8dc5f.yougetaclaw.com,claw-28c43-c8dc5f.apps.ocp.nnsnv.sandbox571.opentlc.com,true
claw-28c43-6a9914.yougetaclaw.com,claw-28c43-6a9914.apps.ocp.nnsnv.sandbox571.opentlc.com,true
```

The public host and OpenShift Route host share the same `claw-{audience}-{user}` prefix. The wildcard DNS `*.yougetaclaw.com` covers all public hosts. The `audience-reset.sh` script generates both hostnames since it already knows the audience code and user code.

## Data Model (SQLite)

```sql
CREATE TABLE routes (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  public_host   TEXT NOT NULL UNIQUE,
  backend_host  TEXT NOT NULL,
  enabled       INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE assignments (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  cookie_value  TEXT NOT NULL UNIQUE,
  route_id      INTEGER NOT NULL REFERENCES routes(id),
  assigned_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE audiences (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  audience_id   TEXT,
  started_at    TEXT NOT NULL DEFAULT (datetime('now')),
  active        INTEGER NOT NULL DEFAULT 1
);
```

## Request Flows

### New user arrives at `yougetaclaw.com`

1. HAProxy receives request with `Host: yougetaclaw.com`.
2. HAProxy forwards to broker backend (`localhost:3000`).
3. Broker checks for `rlb_session` cookie — not found.
4. Broker queries for first unassigned, enabled route:
   ```sql
   SELECT r.id, r.public_host FROM routes r
   LEFT JOIN assignments a ON a.route_id = r.id
   WHERE r.enabled = 1 AND a.id IS NULL
   ORDER BY r.id LIMIT 1
   ```
5. Route found → generate UUID cookie value, insert assignment row.
6. Respond with:
   - `Set-Cookie: rlb_session={uuid}; Domain=yougetaclaw.com; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=86400`
   - `302 Found` with `Location: https://claw-28c43-ef0ea4.yougetaclaw.com`
7. Browser follows redirect. HAProxy map routes `claw-28c43-ef0ea4.yougetaclaw.com` to the OpenShift Route.
8. OpenClaw Gateway UI loads. WebSocket connects directly through HAProxy — broker is not in the path.

### Returning user arrives at `yougetaclaw.com`

1. HAProxy forwards to broker.
2. Broker reads `rlb_session` cookie → looks up assignment:
   ```sql
   SELECT r.public_host FROM assignments a
   JOIN routes r ON r.id = a.route_id
   WHERE a.cookie_value = ?
   ```
3. Assignment found → `302 Found` to `https://claw-28c43-ef0ea4.yougetaclaw.com`.
4. Assignment not found (stale cookie from previous audience) → treat as new user.

### All slots full

1. Broker checks cookie — not found (or stale).
2. No unassigned routes available.
3. Respond with `503 Service Unavailable` and a branded HTML page:
   ```
   All seats are taken for this session.
   Please check with the presenter.
   ```

### User navigates directly to `claw-28c43-ef0ea4.yougetaclaw.com`

HAProxy map routes it directly to OpenShift. The broker is not involved. This works whether or not the user has a cookie — the OpenClaw password gate handles authentication.

## Broker API

| Method | Path | Purpose | Access |
|---|---|---|---|
| `GET` | `/` | Session assignment + 302 redirect (or 503 "full") | Public |
| `GET` | `/status` | Read-only status board HTML (auto-refreshes) | Public |
| `GET` | `/status/api` | JSON: route pool, assignment counts, audience info | Public |
| `POST` | `/admin/reset` | Clear all assignments, reload route pool from `routes.csv` | Localhost or token |
| `POST` | `/admin/release/:slot` | Release a single assignment by route ID | Localhost or token |

### `/admin/reset` behavior

1. Set current audience row to `active=0`.
2. Delete all rows from `assignments`.
3. Delete all rows from `routes`.
4. Re-read `routes.csv` from the local copy at `/var/lib/route-lb/routes.csv` (already downloaded by the `route-lb-sync` timer).
5. Insert new route rows.
6. Extract audience code from first route hostname (the shared `claw-{audience}-*` prefix).
7. Insert new audience row with `active=1`.

### `/admin/release/:slot` behavior

1. Delete the assignment row for the given route ID.
2. The route returns to the available pool.

## Status Board

The status board at `yougetaclaw.com/status` is a read-only HTML page served by the broker. It auto-refreshes every 5 seconds via `fetch('/status/api')`.

It displays:

- **Audience ID** and start time.
- **Summary counters**: assigned, available, unhealthy (if health checks are added later).
- **Route table**: each route's public host, backend host, and assignment status.

No buttons or actions — management is via CLI (`curl -X POST localhost:3000/admin/reset`) or the `audience-reset.sh` script.

## HAProxy Configuration Changes

The existing HAProxy config from `MVP-ROUTE-LB-SETUP.md` needs one addition: a rule to forward bare-domain requests to the broker.

```haproxy
frontend public_http
  bind :8080

  # Health checks (unchanged)
  acl health_path path -i /ready /__lb/healthz
  http-request return status 200 content-type text/plain lf-string "ok\n" if health_path

  # NEW: bare domain goes to broker
  acl is_bare_domain hdr(host) -i yougetaclaw.com
  use_backend broker if is_bare_domain

  # Existing map-based routing for claw-* hosts
  http-request set-var(txn.public_host) req.hdr(Host),lower
  http-request set-var(txn.route_host) var(txn.public_host),map_str(/etc/haproxy/maps/host_to_route.map)
  http-request return status 404 content-type text/plain lf-string "No route mapping for this host\n" unless { var(txn.route_host) -m found }

  http-request set-header Host %[var(txn.route_host)]
  http-request set-header X-Forwarded-Proto https
  http-request set-header X-Forwarded-Host %[var(txn.public_host)]

  default_backend openshift_routes

# NEW: broker backend
backend broker
  server broker 127.0.0.1:3000
```

## Audience Reset Integration

The `audience-reset.sh` script needs a small addition at the end, after all routes are created and gateways are restarted:

```bash
# Generate routes.csv for the load balancer
ROUTES_CSV="$WORK_DIR/routes.csv"
echo "# public_host,openshift_route_host,enabled" > "$ROUTES_CSV"
for idx in "${!AUDIENCE_HOSTS[@]}"; do
  OCP_HOST="${AUDIENCE_HOSTS[$idx]}"
  # Public host uses same prefix but under yougetaclaw.com
  PREFIX=$(echo "$OCP_HOST" | sed "s/\.${APPS_DOMAIN}$//")
  PUBLIC_HOST="${PREFIX}.yougetaclaw.com"
  echo "${PUBLIC_HOST},${OCP_HOST},true" >> "$ROUTES_CSV"
done

# Upload to S3
aws s3 cp "$ROUTES_CSV" "s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY"

# Trigger broker reset
curl -s -X POST http://localhost:3000/admin/reset || \
  ssh route-lb-haproxy "curl -s -X POST http://localhost:3000/admin/reset"
```

Or if the admin is not on the EC2 instance, trigger the reset via SSM:

```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Name,Values=route-lb-haproxy" \
  --parameters 'commands=["curl -s -X POST http://localhost:3000/admin/reset"]'
```

The HAProxy sync timer will pick up the new map from S3 within 30 seconds. The broker reset clears assignments immediately.

## OpenClaw allowedOrigins

Each OpenClaw instance must allow its public `yougetaclaw.com` origin in addition to the OpenShift Route origin. The `audience-reset.sh` script already patches `allowedOrigins` — it needs to also add the `yougetaclaw.com` variant:

```javascript
const origins = c.gateway.controlUi.allowedOrigins || [];
// Existing: add OpenShift Route origin
origins.push('https://claw-28c43-ef0ea4.apps.ocp...');
// NEW: add public yougetaclaw.com origin
origins.push('https://claw-28c43-ef0ea4.yougetaclaw.com');
```

## Deployment on EC2

The broker is installed alongside HAProxy on the same EC2 instance.

### Install

```bash
sudo dnf install -y nodejs
sudo mkdir -p /opt/route-lb-broker
# Copy broker source files to /opt/route-lb-broker
cd /opt/route-lb-broker && npm install
```

### Systemd service

```ini
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
Environment=COOKIE_DOMAIN=yougetaclaw.com

[Install]
WantedBy=multi-user.target
```

### Startup behavior

On startup, the broker:

1. Opens or creates the SQLite database at `DB_PATH`.
2. Creates tables if they don't exist.
3. If `routes` table is empty, reads `ROUTES_CSV_PATH` and populates it.
4. Starts listening on `PORT`.

This means after an EC2 restart, the broker recovers its route pool and assignments from SQLite. No manual intervention needed.

## Failure Behavior

| Condition | Behavior |
|---|---|
| Broker process down | HAProxy returns 503 for bare-domain requests. `claw-*` traffic is unaffected (map routing still works). |
| SQLite DB corrupted | Broker fails to start. Restart with a fresh DB and trigger `/admin/reset`. |
| S3 unavailable during reset | Reset fails. Previous assignments remain active. |
| Stale cookie (previous audience) | Treated as new user — assigned a fresh route. |
| User clears cookies | Treated as new user — assigned a new route. Previous route stays assigned until admin reset. |
| User shares their `claw-*` URL | Other person lands on the same OpenClaw instance. OpenClaw password gate applies. |
| All routes assigned | New visitors get 503 "all seats taken" page. |

## Acceptance Criteria

1. A new visitor to `https://yougetaclaw.com` gets a cookie and is redirected to an available `claw-{audience}-{user}.yougetaclaw.com` URL.
2. The same visitor returning to `https://yougetaclaw.com` is redirected to the same route.
3. When all routes are assigned, new visitors see the 503 "all seats taken" page.
4. `GET /status` shows the current audience ID, assigned/available counts, and route table.
5. `POST /admin/reset` clears all assignments and reloads the route pool.
6. After audience reset, previous cookies are treated as new users.
7. `claw-*` traffic routes directly through HAProxy map — broker is not in the data path after redirect.
8. WebSocket connections work through the redirected `claw-*` URL.
9. Broker and assignments survive EC2 restart (SQLite persistence).
10. The broker starts and serves traffic within 5 seconds of launch.
