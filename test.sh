#!/bin/bash
set -x

# === CONFIGURATION ===
export VAULT_ADDR="https://do-not-delete-ever-v2-public-vault-cf6a1d76.5773df81.z1.hashicorp.cloud:8200"
export VAULT_NAMESPACE="admin"
export OIDC_AUTH_MOUNT="auth0"
export OIDC_ROLE="default"
export REDIRECT_URI="http://localhost:8250/oidc/callback"
export LISTEN_PORT=8250
export KV_PATH="kv/data/test"

# === FUNCTIONS ===

# Extract and clean a query parameter from a URL
extract_query_param_encoded() {
  local url="$1"
  local param="$2"
  echo "$url" \
    | grep -oE "[?&]$param=[^& ]*" \
    | sed "s/^.*$param=//" \
    | sed 's/ HTTP\/1\.1$//' \
    | tr -d '\n\r[:space:]'
}

# Start listener using netcat and capture single line from callback
start_callback_listener() {
  echo "[🔄] Waiting for OIDC callback on http://localhost:$LISTEN_PORT/oidc/callback ..."

  # Use a named pipe
  PIPE=$(mktemp -u)
  mkfifo "$PIPE"

  # Start netcat in background, redirecting to the pipe
  nc -l "$LISTEN_PORT" > "$PIPE" &
  NC_PID=$!

  # Read only the first line (GET /oidc/callback?code=...&state=... HTTP/1.1)
  IFS= read -r CALLBACK_LINE < "$PIPE"

  # Cleanup
  rm "$PIPE"
  kill "$NC_PID" 2>/dev/null

  echo "$CALLBACK_LINE"
}

# === MAIN LOGIN PROCESS ===

echo "[1] Requesting OIDC login URL from Vault..."
LOGIN_REQ=$(curl -s --request POST \
  --header "X-Vault-Namespace: $VAULT_NAMESPACE" \
  --data '{"role":"'"$OIDC_ROLE"'","redirect_uri":"'"$REDIRECT_URI"'"}' \
  "$VAULT_ADDR/v1/auth/$OIDC_AUTH_MOUNT/oidc/auth_url")

AUTH_URL=$(echo "$LOGIN_REQ" | jq -r '.data.auth_url')

if [[ -z "$AUTH_URL" || "$AUTH_URL" == "null" ]]; then
  echo "❌ Failed to get auth URL. Check Vault configuration."
  exit 1
fi

echo "[2] Open the following URL in your browser:"
echo "$AUTH_URL"
xdg-open "$AUTH_URL" 2>/dev/null || open "$AUTH_URL" || echo "↪️ Please open it manually."

# Step 3: Wait for login redirect
CALLBACK_LINE=$(start_callback_listener)

# Step 4: Parse response
echo "[4] Extracting code/state/nonce..."
CODE=$(extract_query_param_encoded "$CALLBACK_LINE" "code")
STATE=$(extract_query_param_encoded "$CALLBACK_LINE" "state")
#NONCE=$(extract_query_param_encoded "$AUTH_URL" "nonce")

echo "→ Code:  $CODE"
echo "→ State: $STATE"
#echo "→ Nonce: $NONCE"

# Step 5: Build callback URL
CALLBACK_URL="$VAULT_ADDR/v1/auth/$OIDC_AUTH_MOUNT/oidc/callback?state=$STATE&code=$CODE"
echo "[5] Callback URL:"
echo "$CALLBACK_URL"

# Step 6: Complete login
echo "[6] Exchanging code for Vault token..."
RESPONSE=$(curl -s --request GET \
  --header "X-Vault-Namespace: $VAULT_NAMESPACE" \
  "$CALLBACK_URL")

VAULT_TOKEN=$(echo "$RESPONSE" | jq -r '.auth.client_token')

if [[ -n "$VAULT_TOKEN" && "$VAULT_TOKEN" != "null" ]]; then
  echo "🎉 Login successful!"
  echo "Vault Token: $VAULT_TOKEN"
  export VAULT_TOKEN="$VAULT_TOKEN"
else
  echo "❌ Login failed."
  echo "$RESPONSE"
  exit 1
fi

export SECRET=$(curl -X "GET"  -H "accept: application/json" -H "X-Vault-Token: $VAULT_TOKEN" -H "X-Vault-Namespace: $VAULT_NAMESPACE" $VAULT_ADDR/v1/$KV_PATH)

echo $SECRET | jq .data.data