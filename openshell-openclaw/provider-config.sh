#!/usr/bin/env bash
# provider-config.sh — sourced by all deploy scripts
#
# Reads LLM_PROVIDER (default: anthropic) and exports provider-specific
# variables used by 2-port-forward-openshell.sh, 3-deploy-openclaw-sandbox.sh,
# and 4-configure-openclaw.sh.
#
# Supported providers: anthropic, openai, vllm

LLM_PROVIDER="${LLM_PROVIDER:-anthropic}"

case "$LLM_PROVIDER" in
  anthropic)
    PROVIDER_NAME="anthropic"
    PROVIDER_API_KEY_VAR="ANTHROPIC_API_KEY"
    PROVIDER_API_KEY="${ANTHROPIC_API_KEY:-}"
    MODEL_PRIMARY="anthropic/claude-sonnet-4-6"
    MODEL_ALIAS="Claude"
    AUTH_PROFILE_NAME="anthropic:default"
    AUTH_PROVIDER="anthropic"
    PLUGIN_NAME="anthropic"
    ;;
  openai)
    PROVIDER_NAME="openai"
    PROVIDER_API_KEY_VAR="OPENAI_API_KEY"
    PROVIDER_API_KEY="${OPENAI_API_KEY:-}"
    MODEL_PRIMARY="openai/gpt-5"
    MODEL_ALIAS="GPT"
    AUTH_PROFILE_NAME="openai:default"
    AUTH_PROVIDER="openai"
    PLUGIN_NAME="openai"
    ;;
  vllm)
    PROVIDER_NAME="vllm"
    PROVIDER_API_KEY_VAR="VLLM_API_KEY"
    PROVIDER_API_KEY="${VLLM_API_KEY:-}"
    VLLM_MODEL="${VLLM_MODEL:-qwen3-14b}"
    VLLM_BASE_URL="${VLLM_BASE_URL:-https://litellm-prod.apps.maas.redhatworkshops.io/v1}"
    MODEL_PRIMARY="openai/${VLLM_MODEL}"
    MODEL_ALIAS="${VLLM_MODEL}"
    AUTH_PROFILE_NAME="openai:default"
    AUTH_PROVIDER="openai"
    PLUGIN_NAME="openai"
    ;;
  *)
    echo "ERROR: Unknown LLM_PROVIDER='$LLM_PROVIDER'. Use: anthropic, openai, or vllm"
    exit 1
    ;;
esac
