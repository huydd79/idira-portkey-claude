#!/bin/bash
# idira-get-jwt.sh (generated from idira-get-jwt.sh-original by install.sh)
# ------------------------------------------------------------------
# Helper to obtain a JWT from CyberArk Identity using Authorization
# Code + PKCE (RFC 7636) - PUBLIC CLIENT, no client_secret involved.
# Pure bash (curl + nc + openssl + jq), no python required.
#
# Intended as Claude Code's apiKeyHelper: prints the JWT to STDOUT
# only, every other message/log goes to STDERR. Caches the token at
# $HOME/.cache/idira_auth/tokens.json and reuses it while still valid.
#
# NOTE: This app does NOT support Device Code Flow (verified via its
# .well-known/openid-configuration - no device_authorization_endpoint
# field). That is why PKCE is used instead of Device Flow.
#
# NOTE: CyberArk Identity requires a client_secret for the
# grant_type=refresh_token call (verified empirically - PKCE alone is
# only accepted for the initial authorization_code exchange, not for
# refresh). To keep this script 100% secret-free, it does NOT attempt
# to refresh: once the access token expires, it simply re-opens the
# browser for a fresh login.
#
# DO NOT EDIT THE GENERATED idira-get-jwt.sh DIRECTLY - edit THIS file
# (idira-get-jwt.sh-original) and/or config.sh, then re-run
# ./install.sh to regenerate.
# ------------------------------------------------------------------

CLIENT_ID="94785ff3-cd61-4964-b371-235770445adf"
AUTHORIZE_URL="https://acp4877.id.cyberark.cloud/OAuth2/Authorize/oidc_portkey_jwt"
TOKEN_URL="https://acp4877.id.cyberark.cloud/OAuth2/Token/oidc_portkey_jwt"
REDIRECT_URI="http://localhost:8787/callback"
SCOPE="openid profile email completions.write"

CACHE_DIR="$HOME/.cache/idira_auth"
TOKEN_FILE="$CACHE_DIR/tokens.json"
mkdir -p "$CACHE_DIR"

get_now() { date +%s; }

log() { echo "$@" >&2; }

# ------------------------------------------------------------------
# urlencode / urldecode in pure bash (no jq/python dependency)
# ------------------------------------------------------------------
urlencode() {
  local s="$1" out="" i c
  for (( i=0; i<${#s}; i++ )); do
    c="${s:$i:1}"
    case "$c" in
      [-_.~a-zA-Z0-9]) out+="$c" ;;
      *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
    esac
  done
  printf '%s' "$out"
}

urldecode() {
  local s="${1//+/ }"
  printf '%b' "${s//%/\\x}"
}

# ------------------------------------------------------------------
# STEP 1: Cached token still valid -> return immediately
# ------------------------------------------------------------------
if [ -f "$TOKEN_FILE" ]; then
  ACCESS_TOKEN=$(jq -r '.access_token // .id_token // empty' "$TOKEN_FILE" 2>/dev/null)
  EXPIRES_AT=$(jq -r '.expires_at // 0' "$TOKEN_FILE" 2>/dev/null)
  NOW=$(get_now)

  if [ -n "$ACCESS_TOKEN" ] && [ $((EXPIRES_AT - NOW)) -gt 60 ]; then
    echo "$ACCESS_TOKEN"
    exit 0
  fi

  log "[idira-get-jwt] Access token expired, need to log in again via browser."
fi

# ------------------------------------------------------------------
# STEP 2: Full PKCE flow via browser (public client, no secret)
# ------------------------------------------------------------------
command -v curl    >/dev/null 2>&1 || { log "[ERR] curl not found"; exit 1; }
command -v jq      >/dev/null 2>&1 || { log "[ERR] jq not found"; exit 1; }
command -v nc      >/dev/null 2>&1 || { log "[ERR] nc (netcat) not found"; exit 1; }
command -v openssl >/dev/null 2>&1 || { log "[ERR] openssl not found"; exit 1; }

CODE_VERIFIER=$(openssl rand -base64 48 | tr -d '=+/\n' | cut -c1-64)
CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=\n')
STATE=$(openssl rand -hex 16)

PORT=$(printf '%s' "$REDIRECT_URI" | sed -E 's#^https?://[^:/]+:?([0-9]*).*#\1#')
PORT="${PORT:-80}"

AUTH_URL="${AUTHORIZE_URL}?response_type=code"
AUTH_URL+="&client_id=$(urlencode "$CLIENT_ID")"
AUTH_URL+="&redirect_uri=$(urlencode "$REDIRECT_URI")"
AUTH_URL+="&scope=$(urlencode "$SCOPE")"
AUTH_URL+="&state=${STATE}"
AUTH_URL+="&code_challenge=${CODE_CHALLENGE}"
AUTH_URL+="&code_challenge_method=S256"

log "--------------------------------------------------------"
log "SSO login required via browser (PKCE, no client_secret)."
log "If the browser does not open automatically, visit:"
log "$AUTH_URL"
log "--------------------------------------------------------"

RESPONSE_BODY='<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Login successful</title></head>
<body>
  <h3>&#9989; Login successful</h3>
  <p>You can close this tab and return to the terminal.</p>
</body>
</html>'
RESPONSE_HTTP=$'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: '"${#RESPONSE_BODY}"$'\r\nConnection: close\r\n\r\n'"${RESPONSE_BODY}"

TMP_REQ="$(mktemp)"
trap 'rm -f "$TMP_REQ"' EXIT

( printf '%s' "$RESPONSE_HTTP" | nc -l -w 300 "$PORT" > "$TMP_REQ" 2>/tmp/idira_nc_err.txt ) &
NC_PID=$!
sleep 0.3

if command -v open >/dev/null 2>&1; then
  open "$AUTH_URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$AUTH_URL"
fi

wait "$NC_PID"
REQUEST="$(cat "$TMP_REQ")"

REQUEST_LINE=$(printf '%s\n' "$REQUEST" | head -n1)
RAW_PATH=$(printf '%s' "$REQUEST_LINE" | awk '{print $2}')
QUERY="${RAW_PATH#*\?}"

CODE=""
STATE_RECV=""
ERR=""
IFS='&' read -ra PAIRS <<< "$QUERY"
for p in "${PAIRS[@]}"; do
  key="${p%%=*}"
  val="${p#*=}"
  case "$key" in
    code)  CODE="$(urldecode "$val")" ;;
    state) STATE_RECV="$val" ;;
    error) ERR="$(urldecode "$val")" ;;
  esac
done

if [ -n "$ERR" ]; then
  log "[ERR] OAuth returned error: $ERR"
  exit 1
fi
if [ -z "$CODE" ]; then
  log "[ERR] No 'code' received from callback. Raw request:"
  log "$REQUEST"
  exit 1
fi
if [ "$STATE_RECV" != "$STATE" ]; then
  log "[ERR] State mismatch (CSRF check failed): expected=$STATE got=$STATE_RECV"
  exit 1
fi

# ------------------------------------------------------------------
# STEP 3: Exchange code for token - NO client_secret, uses code_verifier
# ------------------------------------------------------------------
TOKEN_RES=$(curl -sS -X POST "$TOKEN_URL" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "code=$CODE" \
  --data-urlencode "redirect_uri=$REDIRECT_URI" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "code_verifier=$CODE_VERIFIER")

ACCESS_TOKEN=$(echo "$TOKEN_RES" | jq -r '.access_token // .id_token // empty')
if [ -z "$ACCESS_TOKEN" ]; then
  log "[ERR] Token exchange failed. Response:"
  log "$TOKEN_RES"
  exit 1
fi

EXPIRES_IN=$(echo "$TOKEN_RES" | jq -r '.expires_in // 3600')
EXPIRES_AT=$(( $(get_now) + EXPIRES_IN ))

# refresh_token is intentionally NOT stored: this script never uses it
# (CyberArk Identity requires a client_secret for grant_type=refresh_token
# - see note above). Keeping it on disk would just be a dead 24h-lived
# credential, so it is discarded.
jq -n --arg at "$ACCESS_TOKEN" --argjson exp "$EXPIRES_AT" \
  '{access_token: $at, expires_at: $exp}' > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

log "[idira-get-jwt] Login successful. expires_in=${EXPIRES_IN}s"

echo "$ACCESS_TOKEN"
exit 0
