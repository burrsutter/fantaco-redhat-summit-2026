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
dnf install -y haproxy jq socat nodejs22 gcc-c++ make python3

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

# --- Install broker from S3 ---
mkdir -p /opt/route-lb-broker /var/lib/route-lb
aws s3 cp "s3://__CONFIG_BUCKET__/route-lb/broker.tar.gz" /tmp/broker.tar.gz
tar -xzf /tmp/broker.tar.gz -C /opt/route-lb-broker --strip-components=1
rm -f /tmp/broker.tar.gz
cd /opt/route-lb-broker && npm install --production
cd /

# --- Broker systemd service ---
cat > /etc/systemd/system/route-lb-broker.service <<'BROKERSVC'
[Unit]
Description=Route-LB Session Broker
After=network-online.target haproxy.service

[Service]
Type=simple
WorkingDirectory=/opt/route-lb-broker
ExecStart=/usr/bin/node-22 server.js
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
