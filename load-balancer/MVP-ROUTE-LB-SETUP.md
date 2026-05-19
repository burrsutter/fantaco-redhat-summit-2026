# MVP Setup: AWS Load Balancer with Dynamic OpenShift Route Table

## 1. MVP Decision

Use this design for the first working version:

```text
User browser
  -> Route 53 wildcard DNS
  -> AWS ALB with ACM TLS certificate
  -> HAProxy on EC2
  -> OpenShift ingress/router
  -> OpenShift Route target
```

HAProxy is the component that owns the routing table. The AWS ALB provides the public AWS-managed load balancer, TLS termination, WebSocket-aware connection handling, health checks, and an easy place to add AWS WAF later.

The routing table is rebuilt from a route catalog that you provide. A route catalog update should be enough to add, remove, or replace the public URLs that forward to current OpenShift Routes.

For the OpenClaw Gateway UI, gateway state is in-memory per gateway process. That means route-table forwarding alone is not enough: each established browser connection must remain pinned to the gateway process that accepted it. In this MVP, the OpenShift Route provides pod-level cookie stickiness, while HAProxy preserves the WebSocket connection and forwards the browser's public origin.

## 2. What This MVP Solves

- One AWS-hosted public edge for many short-lived OpenShift Routes.
- Routes can be created, deleted, and recreated with new OpenShift hostnames.
- Public URLs do not require per-route Route 53 changes because DNS uses a wildcard record.
- Rebuilding the routing table is a controlled operation:
  - upload a new route catalog
  - run the sync command, or wait for the sync timer
  - HAProxy validates and reloads gracefully
- Removed mappings return a deliberate `404`.
- Existing invalid mappings fail as upstream errors until the route catalog is corrected.
- OpenClaw Gateway UI traffic, including WebSocket upgrades, stays on the same selected gateway process for the lifetime of the connection.

## 3. MVP Acceptance Criteria

- A new `public_host -> openshift_route_host` mapping becomes active within 60 seconds of uploading `routes.csv`.
- A removed `public_host` returns `404` within 60 seconds of uploading `routes.csv`.
- Updating an existing `public_host` to a new OpenShift Route host moves traffic without changing DNS.
- An invalid route catalog does not replace the last good HAProxy map.
- Restarting HAProxy preserves the last synced route table.
- Restarting the EC2 instance repopulates the route table from S3 without manual file edits.
- WebSocket connections through a mapped public host remain connected through HAProxy and the OpenShift Route.
- The OpenShift Route sets a sticky router cookie when the Route targets more than one gateway pod.
- Health checks use `GET /ready` at the gateway-aware layers.
- `gateway.bind`, `gateway.controlUi.allowedOrigins`, and `gateway.trustedProxies` are configured for traffic through the AWS load balancer URL.

## 4. What This MVP Does Not Solve Yet

- It does not implement one-browser-to-one-pod exclusive session routing from `SPEC.md`.
- It does not use AWS ALB listener rules as the dynamic route table. ALB rules are not a good fit for frequently changing arbitrary OpenShift Route hostnames.
- It does not require direct per-pod routing.
- It does not require a custom OpenShift operator.
- It starts with one HAProxy EC2 instance. Move to an Auto Scaling Group after the route sync is proven.
- It does not add a shared session store to OpenClaw. A reconnect can only recover in-memory state if it lands on the same still-running gateway process.

## 5. Required Inputs

Choose these values before provisioning:

```bash
export AWS_REGION=us-east-1
export DOMAIN=yougetaclaw.com
export CONFIG_BUCKET=yougetaclaw-route-lb-config
export ROUTE_CATALOG_KEY=route-lb/routes.csv
export HAPROXY_PORT=8080
export OPENCLAW_PUBLIC_ORIGIN=https://claw-001.yougetaclaw.com
```

You also need:

- A Route 53 public hosted zone for `$DOMAIN`.
- An ACM certificate for `$DOMAIN` and `*.$DOMAIN` in `$AWS_REGION`.
- An OpenShift cluster whose Routes are reachable from the HAProxy EC2 instance.
- One stable OpenShift router DNS name for HAProxy to connect to.
- One stable OpenShift probe Route host that responds to `GET /ready`.
- OpenClaw gateway config that allows the AWS public origin.

The stable router DNS name can be:

- the OpenShift ingress/router load balancer DNS name, if known, or
- a permanent "probe" OpenShift Route hostname that resolves to the same router as the short-lived Routes.

Example:

```bash
export OPENSHIFT_ROUTER_DNS=route-lb-probe-demo.apps.cluster.example.com
export OPENSHIFT_PROBE_ROUTE_HOST=route-lb-probe-demo.apps.cluster.example.com
```

## 6. Route Catalog Contract

The route catalog is a CSV file stored in S3.

File: `routes.csv`

See `routes.example.csv` in this directory for a starter file.

```csv
# public_host,openshift_route_host,enabled
claw-001.yougetaclaw.com,frontend-a-demo.apps.cluster.example.com,true
claw-002.yougetaclaw.com,frontend-b-demo.apps.cluster.example.com,true
claw-old.yougetaclaw.com,frontend-old-demo.apps.cluster.example.com,false
```

Rules:

- `public_host` is the user-facing hostname under your wildcard domain.
- `openshift_route_host` is the current OpenShift Route host.
- `enabled=false` excludes the mapping from HAProxy.
- Hostnames must be lowercase FQDNs.
- Do not include URL schemes, paths, or trailing slashes.
- Recreated OpenShift Routes should get a new or updated `openshift_route_host` value.

Generated HAProxy map:

```text
claw-001.yougetaclaw.com frontend-a-demo.apps.cluster.example.com
claw-002.yougetaclaw.com frontend-b-demo.apps.cluster.example.com
```

## 7. Step-by-Step AWS Setup

### Step 1: Create Or Confirm Route 53 Hosted Zone

```bash
aws route53 list-hosted-zones-by-name \
  --dns-name "$DOMAIN"
```

If the hosted zone does not exist, create it:

```bash
aws route53 create-hosted-zone \
  --name "$DOMAIN" \
  --caller-reference "route-lb-$(date +%s)"
```

If the domain is registered outside Route 53, delegate the domain to the Route 53 name servers.

### Step 2: Request ACM Certificate

```bash
aws acm request-certificate \
  --region "$AWS_REGION" \
  --domain-name "$DOMAIN" \
  --subject-alternative-names "*.$DOMAIN" \
  --validation-method DNS
```

Create the DNS validation records shown by ACM. Continue only after the certificate status is `ISSUED`.

### Step 3: Create The Route Catalog S3 Bucket

```bash
aws s3 mb "s3://$CONFIG_BUCKET" \
  --region "$AWS_REGION"

aws s3api put-bucket-versioning \
  --bucket "$CONFIG_BUCKET" \
  --versioning-configuration Status=Enabled
```

Upload the initial catalog:

```bash
aws s3 cp routes.csv "s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY"
```

### Step 4: Create Security Groups

Create one security group for the ALB:

- Inbound `443/tcp` from `0.0.0.0/0`.
- Outbound to the HAProxy EC2 security group on `$HAPROXY_PORT`.

Create one security group for the HAProxy EC2 instance:

- Inbound `$HAPROXY_PORT/tcp` only from the ALB security group.
- Inbound `22/tcp` only from your admin IP, or use SSM Session Manager and keep SSH closed.
- Outbound `443/tcp` to the OpenShift router.
- Outbound `443/tcp` to AWS services for S3, SSM, and CloudWatch.

### Step 5: Create EC2 IAM Role

Attach these AWS managed policies for the MVP:

- `AmazonSSMManagedInstanceCore`
- `CloudWatchAgentServerPolicy`

Add a custom policy allowing read access to the route catalog:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yougetaclaw-route-lb-config",
        "arn:aws:s3:::yougetaclaw-route-lb-config/route-lb/*"
      ]
    }
  ]
}
```

Replace the bucket name if you use a different value.

### Step 6: Launch The HAProxy EC2 Instance

Start with:

- AMI: Amazon Linux 2023
- Instance type: `c7g.large` or `c7i.large`
- Subnet: public subnet for MVP, private subnet behind a NAT gateway for a more locked-down setup
- IAM instance profile: the role from Step 5
- Security group: the HAProxy security group from Step 4

Install packages:

```bash
sudo dnf install -y haproxy awscli jq socat
sudo mkdir -p /etc/haproxy/maps /etc/route-lb /var/lib/route-lb
```

### Step 7: Configure HAProxy

Create `/etc/haproxy/haproxy.cfg`:

```haproxy
global
  log stdout format raw local0
  maxconn 20000
  stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners

defaults
  mode http
  log global
  option httplog
  option dontlognull
  option forwardfor
  timeout connect 5s
  timeout client 60s
  timeout server 60s
  timeout http-request 10s
  timeout tunnel 4h

resolvers default_dns
  parse-resolv-conf
  hold valid 30s

frontend public_http
  bind :8080

  acl health_path path -i /ready /__lb/healthz
  http-request return status 200 content-type text/plain lf-string "ok\n" if health_path

  http-request set-var(txn.public_host) req.hdr(Host),lower
  http-request set-var(txn.route_host) var(txn.public_host),map_str(/etc/haproxy/maps/host_to_route.map)

  http-request return status 404 content-type text/plain lf-string "No route mapping for this host\n" unless { var(txn.route_host) -m found }

  http-request set-header Host %[var(txn.route_host)]
  http-request set-header X-Forwarded-Proto https
  http-request set-header X-Forwarded-Host %[var(txn.public_host)]

  default_backend openshift_routes

backend openshift_routes
  option httpchk
  http-check send meth GET uri /ready ver HTTP/1.1 hdr Host __OPENSHIFT_PROBE_ROUTE_HOST__
  server openshift-router __OPENSHIFT_ROUTER_DNS__:443 ssl verify none sni var(txn.route_host) resolvers default_dns check check-ssl check-sni __OPENSHIFT_PROBE_ROUTE_HOST__
```

Replace `__OPENSHIFT_ROUTER_DNS__` and `__OPENSHIFT_PROBE_ROUTE_HOST__`:

```bash
sudo sed -i.bak "s/__OPENSHIFT_ROUTER_DNS__/$OPENSHIFT_ROUTER_DNS/g" /etc/haproxy/haproxy.cfg
sudo sed -i.bak2 "s/__OPENSHIFT_PROBE_ROUTE_HOST__/$OPENSHIFT_PROBE_ROUTE_HOST/g" /etc/haproxy/haproxy.cfg
```

Create an empty map so HAProxy can start:

```bash
sudo touch /etc/haproxy/maps/host_to_route.map
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl enable --now haproxy
```

### Step 8: Install The Route Sync Script

Create `/usr/local/bin/route-lb-sync`:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "route-lb-sync must run as root" >&2
  exit 1
fi

CONFIG_BUCKET="${CONFIG_BUCKET:?CONFIG_BUCKET is required}"
ROUTE_CATALOG_KEY="${ROUTE_CATALOG_KEY:-route-lb/routes.csv}"
MAP_FILE="${MAP_FILE:-/etc/haproxy/maps/host_to_route.map}"
WORK_DIR="${WORK_DIR:-/var/lib/route-lb}"

mkdir -p "$WORK_DIR"

catalog="$WORK_DIR/routes.csv"
new_map="$WORK_DIR/host_to_route.map.new"

aws s3 cp "s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY" "$catalog" >/dev/null

awk -F',' '
  BEGIN { bad = 0 }
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  {
    public_host = tolower($1)
    route_host = tolower($2)
    enabled = tolower($3)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", public_host)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", route_host)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", enabled)

    if (enabled != "true") {
      next
    }

    if (public_host !~ /^[a-z0-9.-]+$/ || route_host !~ /^[a-z0-9.-]+$/) {
      printf("invalid row: %s,%s,%s\n", public_host, route_host, enabled) > "/dev/stderr"
      bad = 1
      next
    }

    print public_host " " route_host
  }
  END { exit bad }
' "$catalog" | sort -u > "$new_map"

cp "$MAP_FILE" "$MAP_FILE.bak"
install -m 0644 "$new_map" "$MAP_FILE"
if ! haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
  echo "haproxy config check failed; rolling back map" >&2
  mv "$MAP_FILE.bak" "$MAP_FILE"
  exit 1
fi
rm -f "$MAP_FILE.bak"
systemctl reload haproxy

echo "route table synced: $(wc -l < "$MAP_FILE") active mappings"
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/route-lb-sync
```

Store environment variables for the script:

```bash
sudo tee /etc/route-lb/env >/dev/null <<EOF
CONFIG_BUCKET=$CONFIG_BUCKET
ROUTE_CATALOG_KEY=$ROUTE_CATALOG_KEY
EOF
```

Run the first sync (sources the env file to verify it is correct):

```bash
sudo bash -c 'source /etc/route-lb/env && /usr/local/bin/route-lb-sync'
```

### Step 9: Add A Sync Timer

Create `/etc/systemd/system/route-lb-sync.service`:

```ini
[Unit]
Description=Sync OpenShift Route catalog into HAProxy map
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/route-lb/env
ExecStart=/usr/local/bin/route-lb-sync
```

Create `/etc/systemd/system/route-lb-sync.timer`:

```ini
[Unit]
Description=Run route-lb-sync every 30 seconds

[Timer]
OnBootSec=15s
OnUnitActiveSec=30s
Unit=route-lb-sync.service

[Install]
WantedBy=timers.target
```

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now route-lb-sync.timer
```

### Step 10: Create The ALB Target Group

Create an HTTP target group:

- Protocol: HTTP
- Port: `$HAPROXY_PORT`
- Target type: instance
- Health check path: `/ready`
- Success codes: `200`

Register the HAProxy EC2 instance as the target.

This target group health check verifies the HAProxy process is accepting traffic. The HAProxy backend health check in Step 7 probes the OpenShift router with `GET /ready` using `$OPENSHIFT_PROBE_ROUTE_HOST`, and the gateway pod readiness probe should also use `GET /ready`.

### Step 11: Create The ALB Listener

Create an internet-facing ALB in at least two public subnets.

Add an HTTPS listener:

- Port: `443`
- Certificate: ACM certificate for `$DOMAIN` and `*.$DOMAIN`
- Default action: forward to the HAProxy target group

For the single-HAProxy MVP, do not enable ALB target group stickiness. Each WebSocket connection is already bound to one ALB target for the lifetime of that TCP connection, and the gateway-pod affinity is handled downstream by the OpenShift Route. When you add multiple HAProxy instances later, keep HAProxy stateless by syncing the same map to every instance; only enable ALB target group stickiness if HAProxy starts storing per-user state.

Optional HTTP listener:

- Port: `80`
- Default action: redirect to HTTPS `443`

### Step 12: Create Wildcard DNS

Create a Route 53 alias record:

```text
*.yougetaclaw.com -> ALB DNS name
```

If you also want the root domain to work:

```text
yougetaclaw.com -> ALB DNS name
```

## 8. Daily Route Table Rebuild Workflow

When OpenShift Routes are recreated:

1. Export or write the new `routes.csv`.
2. Upload it to S3:

   ```bash
   aws s3 cp routes.csv "s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY"
   ```

3. Wait up to 30 seconds for the timer, or force an immediate sync with SSM:

   ```bash
   aws ssm send-command \
     --document-name "AWS-RunShellScript" \
     --targets "Key=tag:Name,Values=route-lb-haproxy" \
     --parameters 'commands=["sudo systemctl start route-lb-sync.service"]'
   ```

4. Verify the public host:

   ```bash
   curl -I "https://claw-001.$DOMAIN/"
   ```

5. Verify the HAProxy map on EC2 if needed:

   ```bash
   echo "show map /etc/haproxy/maps/host_to_route.map" | sudo socat - /run/haproxy/admin.sock
   ```

## 9. Optional: Generate The Catalog From OpenShift

If the source of truth is a namespace and label selector, generate `routes.csv` with `oc`:

```bash
oc get routes -n demo \
  -l route-lb/enabled=true \
  -o jsonpath='{range .items[*]}{.metadata.annotations.route-lb\.public-host}{","}{.spec.host}{",true\n"}{end}' \
  > routes.csv
```

Each Route needs this annotation:

```yaml
metadata:
  annotations:
    route-lb.public-host: claw-001.yougetaclaw.com
  labels:
    route-lb/enabled: "true"
```

## 10. OpenShift Route Requirements

Each target OpenShift Route must:

- Be reachable from the HAProxy EC2 instance.
- Respond correctly when `Host` and SNI are set to the OpenShift Route host.
- Use HTTPS on the OpenShift router for the MVP.
- Route to OpenClaw gateway pods that listen on all pod interfaces.
- Preserve sticky routing to the selected gateway pod when more than one gateway pod is behind the Route.
- Have `GET /ready` return success only when the gateway is ready.

Recommended Route annotations:

```yaml
metadata:
  annotations:
    router.openshift.io/cookie_name: OPENCLAW_ROUTE
    haproxy.router.openshift.io/timeout: 4h
```

The `router.openshift.io/cookie_name` annotation gives the OpenShift router a stable sticky-session cookie name for this Route. Do not set `haproxy.router.openshift.io/disable_cookies: "true"` for OpenClaw Gateway UI Routes.

If each public Route targets exactly one gateway pod, pod-level stickiness is naturally satisfied for that Route. If a Route targets a Service with multiple gateway pods, the OpenShift router cookie is required so reconnects and follow-up HTTP requests are sent back to the same gateway pod when possible.

Recommended gateway Deployment readiness probe:

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 18789
  initialDelaySeconds: 5
  periodSeconds: 5
```

Recommended OpenClaw gateway config values:

```json
{
  "gateway": {
    "bind": "lan",
    "trustedProxies": [
      "<alb-subnet-cidr>",
      "<haproxy-ec2-private-ip-or-subnet-cidr>",
      "<openshift-ingress-source-cidr>"
    ],
    "controlUi": {
      "allowedOrigins": [
        "https://claw-001.yougetaclaw.com"
      ]
    }
  }
}
```

For the route-table MVP, `allowedOrigins` must include the AWS public URL, not just the internal OpenShift Route host. If one OpenClaw deployment is reused behind several public hosts, include every public origin that can reach that gateway.

Quick direct test:

```bash
curl -kI "https://frontend-a-demo.apps.cluster.example.com/ready"
```

Quick through-AWS test:

```bash
curl -I "https://claw-001.yougetaclaw.com/ready"
```

Sticky-cookie smoke test:

```bash
curl -ksSI -c /tmp/openclaw-cookie.jar "https://claw-001.yougetaclaw.com/" | grep -Ei 'set-cookie|http/'
curl -ksSI -b /tmp/openclaw-cookie.jar "https://claw-001.yougetaclaw.com/" | grep -Ei 'http/'
```

## 11. Failure Behavior

| Condition | MVP behavior |
| --- | --- |
| Public host not in map | `404 No route mapping for this host` |
| Route exists in map but OpenShift Route was deleted | HAProxy upstream failure, usually `503` |
| Gateway pod becomes unready | OpenShift stops routing new requests to that pod; existing WebSocket connection eventually disconnects |
| Gateway pod dies | In-memory OpenClaw chat/connection state for that pod is lost |
| Browser reconnects after pod death | May land on a different ready pod; previous in-memory state is not recovered |
| Bad CSV syntax | Sync fails; previous map remains active |
| S3 unavailable | Sync fails; previous map remains active |
| HAProxy config invalid | Sync fails before reload; previous process remains active |
| HAProxy EC2 down | ALB target unhealthy; MVP is unavailable until EC2 recovers |

## 12. Acceptance Tests

Run these before calling the MVP complete:

1. Add a new OpenShift Route to `routes.csv`, sync, and confirm the new public host returns `200` or the expected app response.
2. Remove a public host from `routes.csv`, sync, and confirm the public host returns `404`.
3. Change a public host to a different OpenShift Route host, sync, and confirm traffic moves to the new target.
4. Delete an OpenShift Route while it is still in `routes.csv` and confirm HAProxy returns an upstream failure instead of routing to a different target.
5. Open the OpenClaw Gateway UI through the public host and confirm the WebSocket connection is established.
6. Confirm the OpenShift Route sets the sticky router cookie on first access.
7. Reuse the cookie jar for a second request and confirm the selected gateway pod remains the same, using gateway logs or a temporary pod-name response/header if available.
8. Confirm `GET /ready` works through the public host and directly through the OpenShift Route.
9. Upload an invalid `routes.csv` and confirm the sync fails without breaking the last good map.
10. Restart HAProxy and confirm the current map is loaded.
11. Restart the EC2 instance and confirm the timer repopulates the route table from S3.

## 13. Post-MVP Hardening

Do these after the MVP path works:

- Replace single EC2 with an Auto Scaling Group across at least two AZs.
- Keep the S3 sync timer on every HAProxy instance so all instances converge on the same map.
- Enable AWS WAF on the ALB or CloudFront.
- Add CloudWatch alarms for ALB `5XX`, target health, and HAProxy process health.
- Add HAProxy access logs to CloudWatch Logs.
- Replace `ssl verify none` with verification against the OpenShift router CA.
- Add a protected admin endpoint or pipeline job that uploads `routes.csv` and triggers sync.
- Add a pre-sync check that confirms each `openshift_route_host` resolves and returns an expected status.
- Add a shared session/state store to OpenClaw only if reconnecting to a different gateway process must preserve chat state.

## 14. References

- [Red Hat OpenShift Route documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/ingress_and_load_balancing/routes): OpenShift supports sticky sessions with router cookies, `router.openshift.io/cookie_name` sets the Route cookie name, and `haproxy.router.openshift.io/disable_cookies` disables cookie tracking when set to `true`.
- [Red Hat OpenShift Route annotations](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/ingress_and_load_balancing/routes): route annotations also include `haproxy.router.openshift.io/timeout`, which is useful for long-running WebSocket and UI connections.

## 15. Relationship To Existing Docs

- `AWS-SETUP.md` remains useful for AWS DNS, TLS, EC2, WAF, and HA notes.
- `SPEC.md` describes a stricter one-browser-to-one-pod session isolation design. That is a different requirement from this route-table MVP.
- `MONITORING-CONTROLLER.md` is useful later if the backend capacity model needs per-pod occupancy metrics.
- `DDOS-STRATEGY.md` is useful after the MVP, especially if this is used for a live event.
- `research-notes.md` contains earlier architecture options; this document narrows the MVP to one actionable path.
