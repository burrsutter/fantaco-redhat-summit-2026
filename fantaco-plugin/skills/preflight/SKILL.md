---
name: preflight
description: Run pre-flight checks before deploying to OpenShift — validates CLI tools, cluster connectivity, .env keys, endpoint reachability, and registry login
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, AskUserQuestion
---

# Pre-Flight Deployment Checks

Run all deployment prerequisites in one pass so problems are caught before wasting time on a failed deploy.

## Step 1: Initialize tracking variables

Set up variables to track results. Use these throughout:

```bash
HARD_FAILS=0
WARNINGS=0
```

## Step 2: Check CLI tools

For each tool (`oc`, `podman`, `helm`), check if it is installed and capture the version.

```bash
# oc
if command -v oc &>/dev/null; then
  OC_VERSION=$(oc version --client 2>/dev/null | head -1)
  echo "  oc       ✓ ${OC_VERSION}"
else
  echo "  oc       ✗ MISSING"
  HARD_FAILS=$((HARD_FAILS + 1))
fi

# podman
if command -v podman &>/dev/null; then
  PODMAN_VERSION=$(podman --version 2>/dev/null)
  echo "  podman   ✓ ${PODMAN_VERSION}"
else
  echo "  podman   ✗ MISSING"
  HARD_FAILS=$((HARD_FAILS + 1))
fi

# helm
if command -v helm &>/dev/null; then
  HELM_VERSION=$(helm version --short 2>/dev/null)
  echo "  helm     ✓ ${HELM_VERSION}"
else
  echo "  helm     ✗ MISSING"
  HARD_FAILS=$((HARD_FAILS + 1))
fi
```

## Step 3: Check OpenShift connectivity

```bash
OC_USER=$(oc whoami 2>/dev/null)
if [ $? -eq 0 ]; then
  OC_PROJECT=$(oc project -q 2>/dev/null)
  echo "  User     ${OC_USER}"
  echo "  Project  ${OC_PROJECT}"
else
  echo "  ✗ Not logged in to OpenShift"
  HARD_FAILS=$((HARD_FAILS + 1))
fi
```

## Step 4: Load and validate `.env`

Look for the `.env` file at the project root (`$PROJECT_ROOT/.env`). If missing, warn and skip this section.

For each variable below, check:
- Present in file and not empty and not `CHANGE_ME` → `✓ set`
- Present but empty or equals `CHANGE_ME` → `⚠ placeholder / not set` (increment WARNINGS)
- Not present in file → `⚠ not set` (increment WARNINGS)

Variables to check (all optional — no hard failures):

| Variable | Validation |
|----------|------------|
| `OPENAI_API_KEY` | Not empty, not `CHANGE_ME` |
| `LLM_API_KEY` | Not empty, not `CHANGE_ME` |
| `LLM_API_BASE_URL` | Not empty, starts with `http` |
| `LLM_MODEL_NAME` | Not empty |
| `ANTHROPIC_API_KEY` | Not empty, not `CHANGE_ME` |
| `TELEGRAM_BOT_TOKEN` | Not empty, not `CHANGE_ME` |
| `TELEGRAM_USER_ID` | Not empty, not `CHANGE_ME` |
| `MODEL_API_KEY` | Not empty, not `CHANGE_ME` |

```bash
ENV_FILE="${PROJECT_ROOT}/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "  ⚠ .env file not found at ${ENV_FILE}"
  WARNINGS=$((WARNINGS + 1))
else
  # source the file to get values
  set -a
  source "$ENV_FILE"
  set +a

  for VAR in OPENAI_API_KEY LLM_API_KEY LLM_API_BASE_URL LLM_MODEL_NAME ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_USER_ID MODEL_API_KEY; do
    VALUE="${!VAR}"
    if [ -z "$VALUE" ]; then
      printf "  %-20s ⚠ not set\n" "$VAR"
      WARNINGS=$((WARNINGS + 1))
    elif [ "$VALUE" = "CHANGE_ME" ]; then
      printf "  %-20s ⚠ CHANGE_ME (placeholder)\n" "$VAR"
      WARNINGS=$((WARNINGS + 1))
    else
      # For LLM_API_BASE_URL, also check it starts with http
      if [ "$VAR" = "LLM_API_BASE_URL" ]; then
        if [[ "$VALUE" != http* ]]; then
          printf "  %-20s ⚠ invalid URL: %s\n" "$VAR" "$VALUE"
          WARNINGS=$((WARNINGS + 1))
        else
          printf "  %-20s ✓ %s\n" "$VAR" "$VALUE"
        fi
      else
        # Truncate display of secrets
        DISPLAY="${VALUE:0:8}..."
        printf "  %-20s ✓ set\n" "$VAR"
      fi
    fi
  done
fi
```

## Step 4b: Prompt for missing LLM_API_KEY

After validating `.env`, check whether `LLM_API_KEY` is missing, empty, or set to `CHANGE_ME`. If so, use the `AskUserQuestion` tool to ask the user:

> "The LiteLLM MaaS API key (`LLM_API_KEY`) is not set in `.env`. Please provide it so we can verify endpoint connectivity."

If the user provides a key:
1. Export it for the current run: `export LLM_API_KEY="<value>"`
2. Write or update it in the `.env` file so future runs pick it up automatically. If `.env` already has an `LLM_API_KEY=` line, replace it; otherwise append it.

If the user skips or declines, continue without it — the endpoint check will run unauthenticated and likely show a warning.

## Step 5: Check endpoint reachability

If `LLM_API_BASE_URL` is set and starts with `http`, curl its `/v1/models` endpoint using `LLM_API_KEY` as a Bearer token (the LiteLLM MaaS proxy requires authentication):

```bash
if [ -n "$LLM_API_BASE_URL" ] && [[ "$LLM_API_BASE_URL" == http* ]]; then
  AUTH_HEADER=""
  if [ -n "$LLM_API_KEY" ]; then
    AUTH_HEADER="-H \"Authorization: Bearer ${LLM_API_KEY}\""
  fi
  HTTP_CODE=$(eval curl -sk -o /dev/null -w "%{http_code}" --max-time 5 ${AUTH_HEADER} "${LLM_API_BASE_URL}/v1/models" 2>/dev/null)
  if [[ "$HTTP_CODE" =~ ^[23] ]]; then
    echo "  LLM API  ✓ reachable (${HTTP_CODE})"
  else
    echo "  LLM API  ⚠ unreachable (HTTP ${HTTP_CODE})"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  echo "  LLM API  — skipped (no URL configured)"
fi
```

## Step 6: Check Docker Hub authentication

```bash
DOCKER_USER=$(podman login --get-login docker.io 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$DOCKER_USER" ]; then
  echo "  docker.io  ✓ logged in as ${DOCKER_USER}"
else
  echo "  docker.io  ⚠ not logged in"
  WARNINGS=$((WARNINGS + 1))
fi
```

## Step 7: Print summary report

Combine all results into a formatted summary table. Use the format below:

```
Pre-Flight Check Results
========================
CLI Tools:
  oc       ✓ <version>
  podman   ✓ <version>
  helm     ✓ <version>

OpenShift:
  User     <user>
  Project  <project>

Environment (.env):
  OPENAI_API_KEY      ✓ set
  LLM_API_KEY         ⚠ CHANGE_ME (placeholder)
  LLM_API_BASE_URL    ✓ https://...
  LLM_MODEL_NAME      ✓ qwen3-14b
  ANTHROPIC_API_KEY   ⚠ not set
  TELEGRAM_BOT_TOKEN  ⚠ not set
  MODEL_API_KEY       ⚠ not set

Endpoints:
  LLM API  ✓ reachable (200)  [authenticated via LLM_API_KEY]

Registry:
  docker.io  ✓ logged in as <user>

Result: READY (N warnings)
```

**Final result logic:**
- If `HARD_FAILS > 0` → print `Result: NOT READY` and list what must be fixed (missing CLI tools, not logged into OpenShift)
- If `HARD_FAILS == 0` → print `Result: READY` with warning count if any

Run all checks as a **single bash script** so the summary table is printed in one block. Do not run checks interactively one at a time.
