---
name: openshell-policy-logs
description: Debug sandbox connectivity, proxy, networking, and policy issues by finding and analyzing OpenClaw and OpenShell sandbox logs. Use when a sandbox request is blocked, connectivity fails, proxy errors appear, or policy changes don't take effect. Trigger keywords - policy logs, sandbox logs, blocked request, denied connection, proxy error, ECONNREFUSED, connectivity issue, debug policy, debug proxy, network denied, check logs, fetch failed, Undici error, DNS failure.
---

# Debug Sandbox Policy and Connectivity

Diagnose sandbox networking, proxy, and policy enforcement issues in the OpenClaw + OpenShell demo environment.

## Overview

Use this skill when:
- A sandbox request is blocked or returns an error
- `ECONNREFUSED`, `ETIMEDOUT`, or Undici fetch errors appear
- A newly added policy endpoint is not working
- DNS resolution fails inside the sandbox
- Proxy bypass or connectivity failures occur
- You need to verify what the proxy allowed or denied

## Prerequisites

Before starting, confirm:
- `openshell` CLI is registered to a gateway (`openshell status` succeeds)
- `oc` is logged in to the cluster (`oc whoami` succeeds)
- A sandbox is running (`openshell sandbox list` shows at least one sandbox)

If any prerequisite fails, fix it before proceeding. The helper wrapper is at `openshell-openclaw/openshell.sh`.

## Step 1: Identify the Sandbox and Pod

Resolve the sandbox name and the underlying Kubernetes pod.

```bash
# Get sandbox name
SANDBOX_NAME=$(openshell sandbox list 2>/dev/null | sed $'s/\x1b\\[[0-9;]*m//g' | grep -v '^NAME' | awk '{print $1}' | head -1)
echo "Sandbox: $SANDBOX_NAME"

# Get the pod name
NAMESPACE=$(oc project -q 2>/dev/null || echo openshell)
POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" --no-headers | awk '{print $1}' | head -1)
echo "Pod: $POD  Namespace: $NAMESPACE"
```

If `SANDBOX_NAME` is empty, no sandbox is running. Re-run `openshell-openclaw/3-deploy-openclaw-sandbox.sh`.

## Step 2: Check OpenClaw Gateway Logs

The OpenClaw gateway writes to `/tmp/gateway.log` inside the pod. This shows application-level errors (fetch failures, proxy connection errors, Undici errors).

```bash
# View last 30 lines of gateway log
oc exec "$POD" -n "$NAMESPACE" -- cat /tmp/gateway.log | tail -30

# Search for errors
oc exec "$POD" -n "$NAMESPACE" -- cat /tmp/gateway.log | grep -iE 'error|fail|ECONNREFUSED|Undici'
```

**What to look for:**

| Pattern | Meaning |
|---------|---------|
| `ECONNREFUSED 10.200.0.1:3128` | Proxy not reachable — gateway may not be in sandbox namespace |
| `UND_ERR_CONNECT_TIMEOUT` | Proxy connection timed out — check proxy is running |
| `fetch failed` | Upstream request failed after proxy — check policy denial |
| `TypeError: fetch failed` | Undici could not complete the request — multiple possible causes |
| `ENOTFOUND <host>` | DNS resolution failed inside sandbox — needs `/etc/hosts` entry |

If the gateway log is empty or missing, the gateway process is not running. Re-run `openshell-openclaw/4-configure-openclaw.sh`.

## Step 3: Check Sandbox Proxy Logs (OCSF)

The sandbox proxy logs are the primary debugging source. They show every network decision the proxy made (allow, deny, bypass detection) in OCSF format.

### Via openshell CLI

```bash
# Live-stream logs
openshell logs "$SANDBOX_NAME" --tail

# Recent logs (last 5 minutes)
openshell logs "$SANDBOX_NAME" --since 5m

# Denials only (warnings and above)
openshell logs "$SANDBOX_NAME" --level warn --since 10m
```

### Via direct filesystem access

```bash
# Read the current day's OCSF log file inside the sandbox
openshell sandbox connect "$SANDBOX_NAME" -- cat /var/log/openshell.$(date +%Y-%m-%d).log

# Grep for a specific host
openshell sandbox connect "$SANDBOX_NAME" -- cat /var/log/openshell.$(date +%Y-%m-%d).log | grep 'api.nasa.gov'
```

## Step 4: Interpret OCSF Log Patterns

The proxy emits structured OCSF shorthand logs. Here is how to read them:

| Log pattern | Meaning |
|-------------|---------|
| `NET:OPEN [INFO] ALLOWED` | TCP connection allowed by policy |
| `NET:OPEN [MED] DENIED` | TCP connection blocked — host/port not in policy |
| `HTTP:GET [INFO] ALLOWED` | HTTP GET request allowed by L7 rule |
| `HTTP:GET [MED] DENIED` | HTTP GET blocked by L7 rule |
| `HTTP:POST [MED] DENIED` | HTTP POST blocked — method not permitted |
| `HTTP:CONNECT [INFO] ALLOWED` | HTTPS tunnel established (L4-only endpoint) |
| `CONFIG:LOADED [INFO]` | Policy reload succeeded |
| `CONFIG:LOADED [MED]` | Policy reload with warnings |
| `FINDING:DETECTION [HIGH]` | Security finding — proxy bypass attempt detected |
| `SSH:AUTH [INFO] ALLOWED` | SSH authentication succeeded |
| `PROC:START [INFO]` | Process started inside sandbox |
| `PROC:EXIT [INFO]` | Process exited normally |
| `PROC:EXIT [CRIT]` | Process killed by timeout |

**Key fields in log lines:**
- The destination host and port appear after `dst=` or in the message text
- The binary that made the request appears after `actor=` or `binary=`
- The policy rule that matched appears after `rule=` or `firewall_rule=`

## Step 5: Common Denial Reasons

When a request is denied, the log message includes a reason. Here are the most common:

| Denial reason | What it means | Fix |
|---------------|--------------|-----|
| `no matching policy` | Host is not in any policy endpoint list | Add the host to the policy YAML and apply with `openshell policy set` |
| `DNS resolution failed` | Host cannot be resolved inside the sandbox | Add an `/etc/hosts` entry (see Step 7) |
| `resolves to always-blocked address` | Target resolved to loopback (127.x) or link-local (169.254.x) | These are always blocked — use a real IP or `allowed_ips` for private ranges |
| `port N is a blocked control-plane port` | Kubernetes control plane port protection | This port is intentionally blocked to protect the cluster |
| `method not allowed` | L7 rule does not permit this HTTP method | Update the policy `rules` or `access` preset |
| `path not allowed` | L7 rule does not match this URL path | Add a rule with the correct path glob |

## Step 6: Check Current Policy

Compare what the proxy is enforcing against what you expect.

```bash
# Full policy with YAML output
openshell policy get "$SANDBOX_NAME" --full

# Quick summary via helper script
./openshell-openclaw/8-current-policy.sh
```

The `8-current-policy.sh` script shows a formatted table of allowed endpoints, methods, and binaries.

**Compare against the policy file:**
- Default policy: `openshell-openclaw/openclaw-policy.default.yaml`
- Working policy (modified by add/remove scripts): `openshell-openclaw/openclaw-policy.yaml`

If the live policy does not match the file, re-apply:

```bash
openshell policy set "$SANDBOX_NAME" --policy openshell-openclaw/openclaw-policy.yaml --wait
```

## Step 7: Common Fixes

### Host not in policy

Run the appropriate policy-add script or add the endpoint manually:

```bash
# Pre-built scripts for common endpoints
./openshell-openclaw/nasa-policy-add.sh
./openshell-openclaw/wttr-policy-add.sh
./openshell-openclaw/hackernews-policy-add.sh
./openshell-openclaw/reddit-policy-add.sh

# Or edit openclaw-policy.yaml manually and apply
openshell policy set "$SANDBOX_NAME" --policy openshell-openclaw/openclaw-policy.yaml --wait
```

### DNS resolution failed

OpenClaw's `web_fetch` tool resolves DNS locally via `getaddrinfo` instead of delegating to the proxy. Pin DNS entries in `/etc/hosts`:

```bash
# Resolve and pin a host
HOST="api.example.com"
IP=$(dig +short "$HOST" A 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
oc exec "$POD" -n "$NAMESPACE" -- sh -c "echo '$IP $HOST' >> /etc/hosts"
```

For persistent DNS pinning, add the host to `HOSTS_TO_PIN` in `openshell-openclaw/4-configure-openclaw.sh` (currently: `api.nasa.gov apod.nasa.gov wttr.in www.reddit.com`).

### Proxy environment variables missing

The gateway must be started with proxy env vars inside the sandbox network namespace. If `ECONNREFUSED` appears on fetch, verify the gateway was started correctly:

```bash
# Check if proxy env vars are set in the gateway process
openshell sandbox exec -n "$SANDBOX_NAME" --no-tty -- sh -c 'cat /proc/$(pgrep -f "openclaw gateway" | head -1)/environ 2>/dev/null | tr "\0" "\n" | grep -i proxy'
```

Expected output should include:
- `HTTP_PROXY=http://10.200.0.1:3128`
- `HTTPS_PROXY=http://10.200.0.1:3128`
- `OPENCLAW_PROXY_ACTIVE=1`

If missing, restart the gateway properly:

```bash
openshell sandbox exec -n "$SANDBOX_NAME" --no-tty -- \
  sh -c 'export HTTP_PROXY=http://10.200.0.1:3128 HTTPS_PROXY=http://10.200.0.1:3128 OPENCLAW_PROXY_ACTIVE=1; nohup openclaw gateway --allow-unconfigured > /tmp/gateway.log 2>&1 &'
```

### Policy not reloading

After `openshell policy set`, check that a `CONFIG:LOADED` event appears in logs:

```bash
openshell logs "$SANDBOX_NAME" --since 1m | grep CONFIG
```

If no `CONFIG:LOADED` appears, the policy set may have failed. Check the command output and ensure `--wait` was used.

### ECONNREFUSED on fetch but proxy is running

The gateway must run inside the **sandbox network namespace**, not the pod's root namespace. Use `openshell sandbox exec`, not `oc exec`:

```bash
# CORRECT — runs inside sandbox namespace (proxy at 10.200.0.1:3128 is reachable)
openshell sandbox exec -n "$SANDBOX_NAME" --no-tty -- openclaw gateway ...

# WRONG — runs in pod root namespace (proxy is not at 10.200.0.1:3128)
oc exec "$POD" -n "$NAMESPACE" -- openclaw gateway ...
```

Note: `oc exec` is fine for reading files, checking processes, and modifying `/etc/hosts` (these work from the root namespace). But the gateway process itself must run via `openshell sandbox exec` to be inside the sandbox network namespace.

## Quick Reference: Grep Patterns

One-liners for common diagnosis tasks:

```bash
# All denials in the last 10 minutes
openshell logs "$SANDBOX_NAME" --level warn --since 10m

# Denials for a specific host
openshell logs "$SANDBOX_NAME" --since 30m | grep -i 'DENIED.*api.nasa.gov'

# All policy reload events
openshell logs "$SANDBOX_NAME" --since 1h | grep 'CONFIG'

# All HTTP-level decisions (L7)
openshell logs "$SANDBOX_NAME" --since 10m | grep 'HTTP:'

# All network-level decisions (L4)
openshell logs "$SANDBOX_NAME" --since 10m | grep 'NET:'

# Security findings
openshell logs "$SANDBOX_NAME" --since 1h | grep 'FINDING'

# Gateway errors (OpenClaw application level)
oc exec "$POD" -n "$NAMESPACE" -- cat /tmp/gateway.log | grep -iE 'error|fail|refused'

# Check if gateway process is alive
oc exec "$POD" -n "$NAMESPACE" -- sh -c 'cat /proc/*/cmdline 2>/dev/null | tr "\0" "\n" | grep openclaw'
```

## Companion Skills

These OpenShell skills provide deeper functionality:

- **`generate-sandbox-policy`** (OpenShell repo) — Generate new policy YAML from plain-language requirements or API docs
- **`debug-openshell-cluster`** (OpenShell repo) — Debug gateway installation, cluster connectivity, and OpenShell infrastructure issues
