# Sourced by the workflows. Every token is masked before anything can print it.
API="${HEX_API_URL:?}"
STATUS=""
LAST=""

# oidc FILE [AUDIENCE]
oidc() {
  local aud="${2:-}"
  [ -n "$aud" ] || aud=$(curl -fsS "$API/oidc/audience" | jq -r .audience)
  curl -fsS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${aud}" | jq -j .value > "$1"
  echo "::add-mask::$(cat "$1")"
}

# exchange SCOPE OIDC_FILE OUT_FILE; the access token lands in OUT_FILE.token
exchange() {
  LAST="$3"
  STATUS=$(curl -sS -o "$3" -w '%{http_code}' -X POST "$API/oauth/token" \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
    --data-urlencode "assertion@$2" \
    --data-urlencode "scope=$1")
  jq -j '.access_token // empty' "$3" > "$3.token" 2>/dev/null || : > "$3.token"
  [ ! -s "$3.token" ] || echo "::add-mask::$(cat "$3.token")"
  echo "exchange $1 -> $STATUS $(jq -c 'del(.access_token)' "$3" 2>/dev/null || head -c 300 "$3")"
}

# api METHOD PATH TOKEN_FILE [BODY_FILE]
api() {
  local body=()
  [ -z "${4:-}" ] || body=(--data-binary "@$4" -H "content-type: application/octet-stream")
  LAST=api.out
  STATUS=$(curl -sS -o api.out -w '%{http_code}' -X "$1" "$API$2" \
    -H "authorization: Bearer $(cat "$3")" "${body[@]}")
  echo "api $1 $2 -> $STATUS $(head -c 300 api.out)"
}

# expect STATUS [ERROR [DESCRIPTION]]
expect() {
  [ "$STATUS" = "$1" ] || { echo "::error::expected $1, got $STATUS"; exit 1; }
  [ -z "${2:-}" ] || [ "$(jq -r .error "$LAST")" = "$2" ] || { echo "::error::expected error $2"; exit 1; }
  [ -z "${3:-}" ] || [ "$(jq -r .error_description "$LAST")" = "$3" ] || { echo "::error::expected description $3"; exit 1; }
  echo "ok: $*"
}

# repo_status URL [TOKEN_FILE]
repo_status() {
  if [ -n "${2:-}" ]; then
    curl -s -o /dev/null -w '%{http_code}' -H "authorization: Bearer $(cat "$2")" "$1"
  else
    curl -s -o /dev/null -w '%{http_code}' "$1"
  fi
}

# wait_for_proceed: poll for tag proceed-$GITHUB_RUN_ID for up to 10 minutes
wait_for_proceed() {
  echo "waiting for tag proceed-$GITHUB_RUN_ID"
  for _ in $(seq 1 60); do
    git ls-remote --exit-code --tags origin "proceed-$GITHUB_RUN_ID" > /dev/null && return 0
    sleep 10
  done
  echo "::error::no proceed tag"; exit 1
}
