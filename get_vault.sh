#!/bin/bash

# === FUNCTION: Get Vault Token & Secrets via OIDC Login ===
get_vault() {
  local namespace=""
  local oidc_role=""
  local kv_paths=()

  # === CLI ARGUMENT PARSING ===
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace)
        namespace="$2"
        shift 2
        ;;
      --role)
        oidc_role="$2"
        shift 2
        ;;
      --path)
        kv_paths+=("$2")
        shift 2
        ;;
      *)
        echo "❌ Unknown option: $1"
        echo "Usage: $0 --namespace <namespace> --role <oidc_role> --path <kv_path> [--path <kv_path> ...]"
        return 1
        ;;
    esac
  done

  if [[ -z "$namespace" || -z "$oidc_role" || ${#kv_paths[@]} -eq 0 ]]; then
    echo "❌ Missing required arguments."
    echo "Usage: $0 --namespace <namespace> --role <oidc_role> --path <kv_path> [--path <kv_path> ...]"
    return 1
  fi

  # === VAULT CONFIG ===
  export VAULT_ADDR="https://do-not-delete-ever-v2-public-vault-cf6a1d76.5773df81.z1.hashicorp.cloud:8200"
  export VAULT_NAMESPACE="$namespace"
  export OIDC_AUTH_MOUNT="auth0"
  export OIDC_ROLE="$oidc_role"
  export REDIRECT_URI="http://localhost:8250/oidc/callback"
  export LISTEN_PORT=8250

  # === HELPERS ===
  extract_query_param_encoded() {
    local url="$1"
    local param="$2"
    echo "$url" \
      | grep -oE "[?&]$param=[^& ]*" \
      | sed "s/^.*$param=//" \
      | sed 's/ HTTP\/1\.1$//' \
      | tr -d '\n\r[:space:]'
  }

  start_callback_listener() {
    echo "[🔄] Waiting for OIDC callback on http://localhost:$LISTEN_PORT/oidc/callback ..."
    PIPE=$(mktemp -u)
    mkfifo "$PIPE"
    nc -l "$LISTEN_PORT" > "$PIPE" &
    NC_PID=$!
    IFS= read -r CALLBACK_LINE < "$PIPE"
    rm "$PIPE"
    kill "$NC_PID" 2>/dev/null
    echo "$CALLBACK_LINE"
  }

  # === OIDC FLOW ===
  echo "[1] Requesting OIDC login URL..."
  LOGIN_REQ=$(curl -s --request POST \
    --header "X-Vault-Namespace: $VAULT_NAMESPACE" \
    --data '{"role":"'"$OIDC_ROLE"'","redirect_uri":"'"$REDIRECT_URI"'"}' \
    "$VAULT_ADDR/v1/auth/$OIDC_AUTH_MOUNT/oidc/auth_url")

  AUTH_URL=$(echo "$LOGIN_REQ" | jq -r '.data.auth_url')

  if [[ -z "$AUTH_URL" || "$AUTH_URL" == "null" ]]; then
    echo "❌ Failed to get auth URL."
    return 1
  fi

  echo "[2] Open the following URL in your browser:"
  echo "$AUTH_URL"
  xdg-open "$AUTH_URL" 2>/dev/null || open "$AUTH_URL" || echo "↪️ Please open it manually."

  CALLBACK_LINE=$(start_callback_listener)

  echo "[3] Extracting values from callback..."
  CODE=$(extract_query_param_encoded "$CALLBACK_LINE" "code")
  STATE=$(extract_query_param_encoded "$CALLBACK_LINE" "state")
  NONCE=$(extract_query_param_encoded "$AUTH_URL" "nonce")

  CALLBACK_URL="$VAULT_ADDR/v1/auth/$OIDC_AUTH_MOUNT/oidc/callback?state=$STATE&code=$CODE&nonce=$NONCE"

  echo "[4] Completing login..."
  RESPONSE=$(curl -s --request GET \
    --header "X-Vault-Namespace: $VAULT_NAMESPACE" \
    "$CALLBACK_URL")

  VAULT_TOKEN=$(echo "$RESPONSE" | jq -r '.auth.client_token')

  if [[ -z "$VAULT_TOKEN" || "$VAULT_TOKEN" == "null" ]]; then
    echo "❌ Login failed."
    echo "$RESPONSE"
    return 1
  fi

  echo "✅ Vault login successful!"
  export VAULT_TOKEN="$VAULT_TOKEN"

  # === FETCH SECRETS ===
  for path in "${kv_paths[@]}"; do
    echo "🔐 Fetching secret at: $path"
    SECRET=$(curl -s \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --header "X-Vault-Namespace: $VAULT_NAMESPACE" \
      "$VAULT_ADDR/v1/$path")

    echo "$SECRET" | jq .data.data
  done
}

# === CALL FUNCTION ===
get_vault "$@"
