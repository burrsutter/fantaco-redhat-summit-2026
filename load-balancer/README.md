# Route-LB: AWS Load Balancer + Session Broker for OpenClaw

Public edge for OpenClaw Gateway instances running on OpenShift. Provides a single stable domain (`yougetaclaw.com`) that assigns audience members to exclusive OpenClaw instances via a session broker, then routes all subsequent traffic through HAProxy to the correct OpenShift Route.

```text
User browser
  → Route 53 wildcard DNS (*.yougetaclaw.com)
    → AWS ALB (TLS termination via ACM certificate)
      → HAProxy on EC2 (:8080)
        ├── bare domain → session broker (:3000) → 302 redirect to assigned claw-* host
        └── claw-* hosts → map lookup → OpenShift ingress/router → gateway pod
```

## Script-Based Setup

All provisioning scripts live in `scripts/`. They are **idempotent** — re-running a script that has already completed will detect existing resources and skip creation.

Scripts communicate via `scripts/.state/` files. Each script writes ARNs, IDs, and DNS names that later scripts read.

### Prerequisites

- AWS CLI configured with credentials for the target account
- `oc` CLI logged in to the target OpenShift cluster
- Update `scripts/00-env.sh` with your domain, bucket name, and OpenShift router DNS

### Execution order

Run from the `load-balancer/scripts/` directory. Source env first:

```bash
source 00-env.sh
```

| # | Script | What it does |
|---|--------|--------------|
| 00 | `00-env.sh` | Shared environment variables (`AWS_REGION`, `DOMAIN`, `CONFIG_BUCKET`, etc.) and creates the `.state/` directory. Source this before running any other script. |
| 01 | `01-create-hosted-zone.sh` | Creates (or confirms) a Route 53 public hosted zone for the domain. Prints name servers for domain delegation. |
| 02 | `02-request-acm-certificate.sh` | Requests an ACM TLS certificate for `yougetaclaw.com` and `*.yougetaclaw.com` using DNS validation. Saves the certificate ARN to `.state/`. |
| 03 | `03-create-dns-validation-records.sh` | Reads the ACM validation CNAME records and creates them in Route 53 to prove domain ownership. |
| 04 | `04-wait-for-certificate.sh` | Polls ACM every 15 seconds until the certificate status is `ISSUED` (up to 10 minutes). |
| 05 | `05-create-s3-bucket.sh` | Creates the S3 config bucket with versioning enabled. Uploads the initial `routes.example.csv` as the route catalog. |
| 06 | `06-create-security-groups.sh` | Discovers the default VPC and creates two security groups: one for the ALB (inbound 80/443 from internet) and one for HAProxy EC2 (inbound 8080 from ALB SG only). |
| 07 | `07-create-iam-role.sh` | Creates the `route-lb-haproxy` IAM role with `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy`, and an inline policy for S3 read access. Creates and attaches an instance profile. |
| 07b | `07b-upload-broker.sh` | Packages the `broker/` source directory into a tarball and uploads it to `s3://<bucket>/route-lb/broker.tar.gz`. Must run before launching EC2 (the instance user-data pulls this tarball). |
| 08 | `08-launch-ec2.sh` | Launches an Amazon Linux 2023 EC2 instance (`c7i.large`) with a user-data script that installs HAProxy, the route-sync timer, and the Node.js session broker. Waits for the instance to reach `running`. |
| 09 | `09-create-alb.sh` | Creates the ALB target group (health check on port 8081 `/ready`), registers the EC2 instance, creates the internet-facing ALB across ≥2 AZs, adds an HTTPS listener (443 → target group) and an HTTP listener (80 → 301 redirect to HTTPS). |
| 10 | `10-create-wildcard-dns.sh` | Creates Route 53 alias A records for `*.yougetaclaw.com` and `yougetaclaw.com` pointing to the ALB. |

### Operational scripts

| Script | What it does |
|--------|--------------|
| `09-broker-reset.sh` | Optionally uploads a new `routes.csv` to S3, then uses SSM Run Command to trigger a route sync and broker reset on the EC2 instance. |
| `list-claw-routes.sh` (in parent dir) | Lists all OpenClaw audience Routes across `agentic-user*` namespaces on OpenShift. |

### After setup

Once all scripts have run, verify end-to-end:

```bash
curl -I "https://yougetaclaw.com/"          # should reach the broker
curl -I "https://claw-001.yougetaclaw.com/"  # should reach an OpenClaw instance
```

## Architecture

### Components on EC2

| Process | Port | Purpose |
|---------|------|---------|
| HAProxy | 8080 | Map-based host routing for `claw-*` hosts to OpenShift Routes |
| HAProxy health | 8081 | Returns `200 "ready"` for ALB target group health checks |
| Session broker (Node.js/Express) | 3000 | Assigns users to exclusive claw instances via cookie, redirects, status board |
| route-lb-sync (systemd timer) | — | Pulls `routes.csv` from S3 every 60s, rebuilds HAProxy backends, reloads |

### Session broker

The broker uses SQLite (`/var/lib/route-lb/broker.db`) to track which audience member is assigned to which OpenClaw instance. On first visit to `yougetaclaw.com`, it sets a cookie and 302-redirects the browser to the assigned `claw-*.yougetaclaw.com` host.

Source: `broker/` directory. See `docs/superpowers/specs/2026-05-23-session-broker-design.md` for the full design.

### Route catalog

The route catalog (`routes.csv`) maps public hosts to OpenShift Route hosts:

```csv
# public_host,openshift_route_host,enabled
claw-28c43-ef0ea4.yougetaclaw.com,claw-28c43-ef0ea4.apps.ocp.nnsnv.sandbox571.opentlc.com,true
```

Upload a new CSV and either wait 60s for the timer or force a sync via `09-broker-reset.sh`.

## Required Inputs

Edit `scripts/00-env.sh` before provisioning:

```bash
export AWS_REGION=us-east-1
export DOMAIN=yougetaclaw.com
export CONFIG_BUCKET=yougetaclaw-route-lb-config
export ROUTE_CATALOG_KEY=route-lb/routes.csv
export HAPROXY_PORT=8080
export OPENSHIFT_ROUTER_DNS=router-default.apps.ocp.nnsnv.sandbox571.opentlc.com
export OPENSHIFT_PROBE_ROUTE_HOST=route-lb-probe.apps.ocp.nnsnv.sandbox571.opentlc.com
export INSTANCE_TYPE=c7i.large
```

## Failure Behavior

| Condition | Behavior |
|-----------|----------|
| Public host not in map | `503` — "no route configured for this host" |
| Route in map but OpenShift Route deleted | HAProxy upstream failure (`502`/`503`) |
| Bad CSV syntax | Sync fails; previous HAProxy config remains active |
| S3 unreachable | Sync fails; previous config remains active |
| EC2 down | ALB marks target unhealthy; all traffic fails until recovery |
| Broker DB lost | Assignments lost; users get new assignments on next visit |

## Teardown: AWS Resource Inventory

To **completely remove** the route-lb infrastructure and stop all AWS billing, delete these resources in the order shown (some depend on others being removed first).

### 1. EC2 instance

```bash
aws ec2 terminate-instances --instance-ids "$(cat scripts/.state/ec2-instance-id)"
aws ec2 wait instance-terminated --instance-ids "$(cat scripts/.state/ec2-instance-id)"
```

### 2. Application Load Balancer + listeners + target group

```bash
ALB_ARN=$(cat scripts/.state/alb-arn)
# Delete listeners (HTTPS and HTTP)
for LISTENER in $(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[*].ListenerArn' --output text); do
  aws elbv2 delete-listener --listener-arn "$LISTENER"
done
# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
# Delete target group
aws elbv2 delete-target-group --target-group-arn "$(cat scripts/.state/target-group-arn)"
```

### 3. Security groups

Wait for ALB deletion to complete (ENIs must be released first):

```bash
aws ec2 delete-security-group --group-id "$(cat scripts/.state/haproxy-sg-id)"
aws ec2 delete-security-group --group-id "$(cat scripts/.state/alb-sg-id)"
```

### 4. IAM role + instance profile

```bash
aws iam remove-role-from-instance-profile --instance-profile-name route-lb-haproxy --role-name route-lb-haproxy
aws iam delete-instance-profile --instance-profile-name route-lb-haproxy
aws iam delete-role-policy --role-name route-lb-haproxy --policy-name route-lb-s3-read
aws iam detach-role-policy --role-name route-lb-haproxy --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam detach-role-policy --role-name route-lb-haproxy --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws iam delete-role --role-name route-lb-haproxy
```

### 5. S3 bucket

```bash
aws s3 rm "s3://yougetaclaw-route-lb-config" --recursive
aws s3api delete-bucket --bucket yougetaclaw-route-lb-config
```

If versioning was used, you must also delete all object versions:

```bash
aws s3api list-object-versions --bucket yougetaclaw-route-lb-config \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json \
  | aws s3api delete-objects --bucket yougetaclaw-route-lb-config --delete file:///dev/stdin
```

### 6. ACM certificate

```bash
aws acm delete-certificate --certificate-arn "$(cat scripts/.state/certificate-arn)" --region us-east-1
```

The ALB must be deleted first (certificates in use cannot be deleted).

### 7. Route 53 records

Delete the wildcard and root alias records, the ACM validation CNAMEs, then (optionally) the hosted zone:

```bash
ZONE_ID=$(cat scripts/.state/hosted-zone-id)

# Delete wildcard + root alias records (use the same CHANGE_BATCH format as creation but with Action: DELETE)
# Delete ACM validation CNAME records

# If you no longer need the hosted zone:
aws route53 delete-hosted-zone --id "$ZONE_ID"
```

If the domain is registered through Route 53, do **not** delete the hosted zone unless you are also releasing the domain.

### 8. Clean up .state directory

```bash
rm -rf scripts/.state/
```

### Full resource checklist

| AWS Service | Resource | Name / Identifier | Billed? |
|-------------|----------|-------------------|---------|
| Route 53 | Hosted zone | `yougetaclaw.com` | $0.50/month + queries |
| Route 53 | A record (wildcard) | `*.yougetaclaw.com` | included in zone |
| Route 53 | A record (root) | `yougetaclaw.com` | included in zone |
| Route 53 | CNAME records | ACM validation | included in zone |
| ACM | Certificate | `yougetaclaw.com` + `*.yougetaclaw.com` | Free (while not deleted) |
| S3 | Bucket | `yougetaclaw-route-lb-config` | Storage + requests |
| S3 | Objects | `route-lb/routes.csv`, `route-lb/broker.tar.gz` | Storage |
| EC2 | Instance | `route-lb-haproxy` (`c7i.large`) | **Primary cost** — compute hourly |
| EC2 | Security group | `route-lb-alb` | Free |
| EC2 | Security group | `route-lb-haproxy` | Free |
| ELB | Application Load Balancer | `route-lb-alb` | **Hourly** + LCU usage |
| ELB | Target group | `route-lb-haproxy-tg` | Free (billed through ALB) |
| ELB | HTTPS listener (443) | on `route-lb-alb` | included in ALB |
| ELB | HTTP listener (80) | on `route-lb-alb` | included in ALB |
| IAM | Role | `route-lb-haproxy` | Free |
| IAM | Instance profile | `route-lb-haproxy` | Free |
| IAM | Inline policy | `route-lb-s3-read` | Free |
| IAM | Managed policy attachments | SSM Core, CloudWatch Agent | Free |

**Primary billing items:** EC2 instance (~$0.085/hr for `c7i.large`), ALB (~$0.0225/hr + LCU), Route 53 hosted zone ($0.50/mo), S3 (minimal). Stopping or terminating the EC2 instance and deleting the ALB eliminates most cost immediately.

## Post-MVP Hardening

- Replace single EC2 with an Auto Scaling Group across ≥2 AZs.
- Enable AWS WAF on the ALB.
- Add CloudWatch alarms for ALB `5XX`, target health, and HAProxy process health.
- Add HAProxy access logs to CloudWatch Logs.
- Replace `ssl verify none` with verification against the OpenShift router CA.
- Add a shared session store to OpenClaw if cross-pod reconnection is needed.

## Related Documentation

- `docs/superpowers/specs/2026-05-23-session-broker-design.md` — Full session broker architecture and data model.
- `docs/superpowers/plans/2026-05-23-session-broker.md` — Implementation plan for the broker.
- `broker/` — Session broker source code (Node.js/Express + SQLite).
- `routes.example.csv` — Starter route catalog template.
