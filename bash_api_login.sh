#!/bin/bash

# === CONFIGURATION ===
export VAULT_ADDR="https://do-not-delete-ever-v2-public-vault-cf6a1d76.5773df81.z1.hashicorp.cloud:8200"
export VAULT_NAMESPACE="admin"
export OIDC_AUTH_MOUNT="auth0"
export OIDC_ROLE="default"
export REDIRECT_URI="http://localhost:8250/oidc/callback"
export LISTEN_PORT=8250
export FILE="test_response"

# === FUNCTIONS ===

# Listen for the OIDC redirect
start_callback_listener() {
  echo "Listening on http://localhost:$LISTEN_PORT/oidc/callback..."
  nc -l "$LISTEN_PORT" > "$FILE" &
}

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

# === MAIN LOGIN PROCESS ===

# Get initial mtime
initial_mtime=$(stat -f "%m" "$FILE" 2>/dev/null || echo 0)

# Step 1: Start OIDC login flow
start_callback_listener
echo "[1] Requesting OIDC auth URL..."
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

# Step 3: Wait for callback to hit local listener
echo "[3] Waiting for login redirect..."
while true; do
  current_mtime=$(stat -f "%m" "$FILE")
  if [[ "$current_mtime" -ne "$initial_mtime" ]]; then
    echo "✅ Callback received!"
    break
  fi
  sleep 1
done
sleep 1
# Step 4: Parse response
echo "[4] Extracting code/state/nonce..."
LINE=$(grep 'GET /oidc/callback' "$FILE")
CODE=$(extract_query_param_encoded "$LINE" "code")
STATE=$(extract_query_param_encoded "$LINE" "state")
NONCE=$(extract_query_param_encoded "$AUTH_URL" "nonce")
sleep 1
echo "→ Code:  $CODE"
echo "→ State: $STATE"
echo "→ Nonce: $NONCE"
sleep 1
# Step 5: Build callback URL
CALLBACK_URL="$VAULT_ADDR/v1/auth/$OIDC_AUTH_MOUNT/oidc/callback?state=$STATE&code=$CODE"
echo "[5] Callback URL:"
echo "$CALLBACK_URL"
sleep 1
# Optional: complete login by calling the callback
echo "[6] Completing login..."
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
