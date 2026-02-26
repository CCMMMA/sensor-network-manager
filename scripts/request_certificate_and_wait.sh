#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [uuid anydesk [output_file]]
  $0 [output_file]

If uuid/anydesk are omitted, they are auto-detected:
- uuid: from reversed host FQDN, using root "it.uniparthenope.meteo"
- anydesk: from AnyDesk CLI/config

Environment variables:
  BASE_URL          API base URL (default: http://127.0.0.1:5000)
  USERNAME          Login username (default: admin)
  PASSWORD          Login password (default: password)
  NEW_PASSWORD      New password used only if first-login password change is required
  POLL_INTERVAL     Seconds between download checks (default: 5)
  MAX_WAIT_SECONDS  Max seconds to wait for certificate upload (default: 600)
  UUID_ROOT         Reverse-FQDN root for uuid (default: it.uniparthenope.meteo)
  ANYDESK_ID        Override auto-detected AnyDesk ID
  COUNTRY           Override auto-detected country
  CITY              Override auto-detected city
  LAT               Override auto-detected latitude
  LON               Override auto-detected longitude

Examples:
  $0
  $0 cert.zip
  $0 my.custom.uuid "123 456 789" cert.zip
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 3 ]; then
  usage
  exit 1
fi

UUID_VALUE="${1:-}"
ANYDESK_VALUE="${2:-}"
OUTPUT_FILE="${3:-certificate-package.bin}"

if [ "$#" -eq 1 ]; then
  UUID_VALUE=""
  ANYDESK_VALUE=""
  OUTPUT_FILE="$1"
fi

BASE_URL="${BASE_URL:-http://127.0.0.1:5000}"
USERNAME="${USERNAME:-admin}"
PASSWORD="${PASSWORD:-password}"
NEW_PASSWORD="${NEW_PASSWORD:-}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-600}"
UUID_ROOT="${UUID_ROOT:-it.uniparthenope.meteo}"
ANYDESK_ID="${ANYDESK_ID:-}"
COUNTRY="${COUNTRY:-}"
CITY="${CITY:-}"
LAT="${LAT:-}"
LON="${LON:-}"

COOKIE_JAR="$(mktemp)"
TMP_BODY="$(mktemp)"
DOWNLOAD_TMP="$(mktemp)"
trap 'rm -f "$COOKIE_JAR" "$TMP_BODY" "$DOWNLOAD_TMP"' EXIT

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

parse_json_field() {
  local json="$1"
  local field="$2"
  python3 -c 'import json,sys
try:
    data = json.loads(sys.argv[1])
    value = data.get(sys.argv[2], "")
    print(value if value is not None else "")
except Exception:
    print("")' "$json" "$field"
}

http_json() {
  local method="$1"
  local url="$2"
  local payload="${3:-}"

  local code
  if [ -n "$payload" ]; then
    code="$(curl -sS -o "$TMP_BODY" -w '%{http_code}' -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X "$method" "$url" \
      -H 'Content-Type: application/json' -d "$payload")"
  else
    code="$(curl -sS -o "$TMP_BODY" -w '%{http_code}' -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X "$method" "$url")"
  fi

  local body
  body="$(cat "$TMP_BODY")"
  printf '%s\n%s' "$code" "$body"
}

lower() {
  tr '[:upper:]' '[:lower:]'
}

reverse_labels() {
  awk -F'.' '{for (i=NF; i>=1; i--) printf (i==NF ? "%s" : ".%s"), $i; print ""}'
}

detect_uuid() {
  local fqdn
  fqdn="$(hostname -f 2>/dev/null || true)"
  if [ -z "$fqdn" ]; then
    fqdn="$(hostname)"
  fi

  fqdn="$(printf '%s' "$fqdn" | lower | sed 's/\.$//')"
  if [ -z "$fqdn" ]; then
    return 1
  fi

  local reversed
  reversed="$(printf '%s' "$fqdn" | reverse_labels)"

  if [ "$reversed" = "$UUID_ROOT" ] || [ "${reversed#${UUID_ROOT}.}" != "$reversed" ]; then
    printf '%s' "$reversed"
  else
    printf '%s.%s' "$UUID_ROOT" "$reversed"
  fi
}

trim_spaces() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

detect_anydesk_id() {
  if [ -n "$ANYDESK_ID" ]; then
    printf '%s' "$ANYDESK_ID"
    return 0
  fi

  local out

  if command -v anydesk >/dev/null 2>&1; then
    out="$(anydesk --get-id 2>/dev/null | head -n 1 | trim_spaces || true)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  fi

  if [ -x "/Applications/AnyDesk.app/Contents/MacOS/AnyDesk" ]; then
    out="$(/Applications/AnyDesk.app/Contents/MacOS/AnyDesk --get-id 2>/dev/null | head -n 1 | trim_spaces || true)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  fi

  local file
  for file in \
    /etc/anydesk/system.conf \
    /etc/anydesk/service.conf \
    /var/lib/anydesk/service.conf \
    "$HOME/.anydesk/user.conf" \
    "$HOME/Library/Application Support/AnyDesk/service.conf"; do
    if [ -f "$file" ]; then
      out="$(grep -E 'ad\.anynet\.id' "$file" 2>/dev/null | head -n 1 | sed -E 's/.*ad\.anynet\.id[[:space:]]*=[[:space:]]*//' | tr -d '\r' | trim_spaces || true)"
      if [ -n "$out" ]; then
        printf '%s' "$out"
        return 0
      fi

      out="$(grep -Eo '[0-9]{3}[ ]?[0-9]{3}[ ]?[0-9]{3,}' "$file" 2>/dev/null | head -n 1 | trim_spaces || true)"
      if [ -n "$out" ]; then
        printf '%s' "$out"
        return 0
      fi
    fi
  done

  return 1
}

detect_geo_fields() {
  local json_country_city json_coords
  json_country_city="$(curl -fsS 'http://ip-api.com/json?fields=country,city' 2>/dev/null || true)"
  json_coords="$(curl -fsS 'http://ip-api.com/json?fields=lat,lon' 2>/dev/null || true)"

  local parsed
  parsed="$(python3 -c 'import json,sys
def parse(s):
    try:
        return json.loads(s) if s else {}
    except Exception:
        return {}
cc = parse(sys.argv[1])
co = parse(sys.argv[2])
vals = [
    str(cc.get("country","") or ""),
    str(cc.get("city","") or ""),
    str(co.get("lat","") if co.get("lat","") is not None else ""),
    str(co.get("lon","") if co.get("lon","") is not None else ""),
]
print("|".join(vals))' "$json_country_city" "$json_coords")"

  printf '%s' "$parsed"
}

if [ -z "$UUID_VALUE" ]; then
  UUID_VALUE="$(detect_uuid || true)"
fi
if [ -z "$UUID_VALUE" ]; then
  echo "Unable to auto-detect uuid from hostname. Provide uuid as argument." >&2
  exit 1
fi

if [ -z "$ANYDESK_VALUE" ]; then
  ANYDESK_VALUE="$(detect_anydesk_id || true)"
fi
if [ -z "$ANYDESK_VALUE" ]; then
  echo "Unable to auto-detect AnyDesk ID. Provide it as second argument or set ANYDESK_ID." >&2
  exit 1
fi

echo "Detected uuid: $UUID_VALUE"
echo "Detected anydesk: $ANYDESK_VALUE"

if [ -z "$COUNTRY" ] || [ -z "$CITY" ] || [ -z "$LAT" ] || [ -z "$LON" ]; then
  GEO_DATA="$(detect_geo_fields || true)"
  if [ -n "$GEO_DATA" ]; then
    AUTO_COUNTRY="$(printf '%s' "$GEO_DATA" | awk -F'|' '{print $1}')"
    AUTO_CITY="$(printf '%s' "$GEO_DATA" | awk -F'|' '{print $2}')"
    AUTO_LAT="$(printf '%s' "$GEO_DATA" | awk -F'|' '{print $3}')"
    AUTO_LON="$(printf '%s' "$GEO_DATA" | awk -F'|' '{print $4}')"

    [ -z "$COUNTRY" ] && COUNTRY="$AUTO_COUNTRY"
    [ -z "$CITY" ] && CITY="$AUTO_CITY"
    [ -z "$LAT" ] && LAT="$AUTO_LAT"
    [ -z "$LON" ] && LON="$AUTO_LON"
  fi
fi

[ -z "$COUNTRY" ] && COUNTRY="unknown"
[ -z "$CITY" ] && CITY="unknown"
[ -z "$LAT" ] && LAT="0"
[ -z "$LON" ] && LON="0"

is_number() {
  printf '%s' "$1" | grep -Eq '^-?[0-9]+([.][0-9]+)?$'
}

if ! is_number "$LAT"; then
  LAT="0"
fi
if ! is_number "$LON"; then
  LON="0"
fi

echo "Detected country/city: $COUNTRY / $CITY"
echo "Detected coordinates: $LAT, $LON"

echo "Logging in as '$USERNAME' to $BASE_URL"
LOGIN_PAYLOAD="{\"username\":$(json_escape "$USERNAME"),\"password\":$(json_escape "$PASSWORD")}" 
LOGIN_RESULT="$(http_json POST "$BASE_URL/login" "$LOGIN_PAYLOAD")"
LOGIN_CODE="$(printf '%s' "$LOGIN_RESULT" | sed -n '1p')"
LOGIN_BODY="$(printf '%s' "$LOGIN_RESULT" | sed -n '2,$p')"

if [ "$LOGIN_CODE" != "200" ]; then
  echo "Login failed (HTTP $LOGIN_CODE): $LOGIN_BODY" >&2
  exit 1
fi

MUST_CHANGE="$(parse_json_field "$LOGIN_BODY" "must_change_password")"
if [ "$MUST_CHANGE" = "True" ] || [ "$MUST_CHANGE" = "true" ]; then
  if [ -z "$NEW_PASSWORD" ]; then
    echo "First-login password change required. Set NEW_PASSWORD and retry." >&2
    exit 1
  fi

  echo "Changing password because first-login enforcement is active"
  CHANGE_PAYLOAD="{\"old_password\":$(json_escape "$PASSWORD"),\"new_password\":$(json_escape "$NEW_PASSWORD")}" 
  CHANGE_RESULT="$(http_json POST "$BASE_URL/change-password" "$CHANGE_PAYLOAD")"
  CHANGE_CODE="$(printf '%s' "$CHANGE_RESULT" | sed -n '1p')"
  CHANGE_BODY="$(printf '%s' "$CHANGE_RESULT" | sed -n '2,$p')"

  if [ "$CHANGE_CODE" != "200" ]; then
    echo "Password change failed (HTTP $CHANGE_CODE): $CHANGE_BODY" >&2
    exit 1
  fi
fi

echo "Creating certificate request"
REQ_PAYLOAD="{\"uuid\":$(json_escape "$UUID_VALUE"),\"anydesk\":$(json_escape "$ANYDESK_VALUE"),\"country\":$(json_escape "$COUNTRY"),\"city\":$(json_escape "$CITY"),\"lat\":$LAT,\"lon\":$LON}" 
REQ_RESULT="$(http_json POST "$BASE_URL/certificate/request" "$REQ_PAYLOAD")"
REQ_CODE="$(printf '%s' "$REQ_RESULT" | sed -n '1p')"
REQ_BODY="$(printf '%s' "$REQ_RESULT" | sed -n '2,$p')"

if [ "$REQ_CODE" != "201" ]; then
  echo "Certificate request failed (HTTP $REQ_CODE): $REQ_BODY" >&2
  exit 1
fi

REFERENCE_ID="$(parse_json_field "$REQ_BODY" "reference_id")"
if [ -z "$REFERENCE_ID" ]; then
  echo "Could not parse reference_id from response: $REQ_BODY" >&2
  exit 1
fi

echo "Request accepted. reference_id=$REFERENCE_ID"
echo "Waiting for certificate upload..."

START_TS="$(date +%s)"
while true; do
  CODE="$(curl -sS -o "$DOWNLOAD_TMP" -w '%{http_code}' -b "$COOKIE_JAR" \
    "$BASE_URL/certificate/download/$REFERENCE_ID")"

  if [ "$CODE" = "200" ]; then
    mv "$DOWNLOAD_TMP" "$OUTPUT_FILE"
    echo "Certificate package downloaded to: $OUTPUT_FILE"
    exit 0
  fi

  BODY="$(cat "$DOWNLOAD_TMP")"

  if [ "$CODE" = "409" ]; then
    :
  elif [ "$CODE" = "403" ] || [ "$CODE" = "404" ]; then
    echo "Download aborted (HTTP $CODE): $BODY" >&2
    exit 1
  else
    echo "Unexpected response while waiting (HTTP $CODE): $BODY" >&2
    exit 1
  fi

  NOW_TS="$(date +%s)"
  ELAPSED=$((NOW_TS - START_TS))
  if [ "$ELAPSED" -ge "$MAX_WAIT_SECONDS" ]; then
    echo "Timeout after ${MAX_WAIT_SECONDS}s waiting for reference_id=$REFERENCE_ID" >&2
    exit 1
  fi

  sleep "$POLL_INTERVAL"
done
