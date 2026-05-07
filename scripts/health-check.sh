#!/usr/bin/env bash

set -euo pipefail

DOMAIN="${DOMAIN:-takedaclinic-shinjuku.jp}"
BASE_URL="${BASE_URL:-https://${DOMAIN}}"
WWW_URL="${WWW_URL:-https://www.${DOMAIN}}"
CERT_WARN_DAYS="${CERT_WARN_DAYS:-30}"
WEBHOOK_URL="${HEALTHCHECK_WEBHOOK_URL:-}"

failures=0
failure_messages=()

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

pass() {
  printf 'PASS  %s\n' "$*"
}

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
  failure_messages+=("$*")
}

fetch() {
  curl -fsSL --max-time 20 "$1"
}

status_code() {
  curl -sS -L -o /dev/null -w '%{http_code}' --max-time 20 "$1" || printf '000'
}

check_url_200() {
  local url="$1"
  local code
  code="$(status_code "$url")"
  if [ "$code" = "200" ]; then
    pass "HTTP 200 ${url}"
  else
    fail "Expected HTTP 200 but got ${code}: ${url}"
  fi
}

check_certificate() {
  log "Checking TLS certificate"

  local end_date epoch now days_left
  end_date="$(
    printf '' |
      openssl s_client -servername "$DOMAIN" -connect "${DOMAIN}:443" 2>/dev/null |
      openssl x509 -noout -enddate 2>/dev/null |
      sed 's/^notAfter=//'
  )"

  if [ -z "$end_date" ]; then
    fail "Could not read TLS certificate expiry for ${DOMAIN}"
    return
  fi

  epoch="$(
    python3 - "$end_date" <<'PY'
import sys
from email.utils import parsedate_to_datetime

dt = parsedate_to_datetime(sys.argv[1])
print(int(dt.timestamp()))
PY
  )"
  now="$(date +%s)"
  days_left=$(( (epoch - now) / 86400 ))

  if [ "$days_left" -lt "$CERT_WARN_DAYS" ]; then
    fail "TLS certificate expires in ${days_left} days (${end_date})"
  else
    pass "TLS certificate valid for ${days_left} days (${end_date})"
  fi
}

check_canonical() {
  log "Checking canonical"

  local html canonical
  if ! html="$(fetch "${BASE_URL}/")"; then
    fail "Could not fetch homepage for canonical check"
    return
  fi

  canonical="<link rel=\"canonical\" href=\"${BASE_URL}/\">"
  if printf '%s' "$html" | grep -Fq "$canonical"; then
    pass "Homepage canonical is ${BASE_URL}/"
  else
    fail "Homepage canonical does not match ${BASE_URL}/"
  fi

  if printf '%s' "$html" | grep -Fq "<meta property=\"og:url\" content=\"${BASE_URL}/\">"; then
    pass "Homepage og:url is ${BASE_URL}/"
  else
    fail "Homepage og:url does not match ${BASE_URL}/"
  fi
}

check_robots() {
  log "Checking robots.txt"

  local robots
  if ! robots="$(fetch "${BASE_URL}/robots.txt")"; then
    fail "Could not fetch robots.txt"
    return
  fi

  if printf '%s\n' "$robots" | grep -Eq '^Allow:[[:space:]]*/[[:space:]]*$'; then
    pass "robots.txt allows crawling"
  else
    fail "robots.txt does not contain Allow: /"
  fi

  if printf '%s\n' "$robots" | grep -Eq '^Disallow:[[:space:]]*/[[:space:]]*$'; then
    fail "robots.txt blocks the whole site with Disallow: /"
  else
    pass "robots.txt does not block the whole site"
  fi

  if printf '%s\n' "$robots" | grep -Fq "Sitemap: ${BASE_URL}/sitemap.xml"; then
    pass "robots.txt sitemap points to ${BASE_URL}/sitemap.xml"
  else
    fail "robots.txt sitemap does not point to ${BASE_URL}/sitemap.xml"
  fi
}

check_sitemap() {
  log "Checking sitemap.xml"

  local sitemap urls count
  if ! sitemap="$(fetch "${BASE_URL}/sitemap.xml")"; then
    fail "Could not fetch sitemap.xml"
    return
  fi

  urls="$(printf '%s\n' "$sitemap" | sed -n 's:.*<loc>\(.*\)</loc>.*:\1:p')"
  count="$(printf '%s\n' "$urls" | grep -c '^http' || true)"

  if [ "$count" -eq 0 ]; then
    fail "sitemap.xml has no URLs"
    return
  fi
  pass "sitemap.xml contains ${count} URLs"

  while IFS= read -r url; do
    [ -z "$url" ] && continue
    case "$url" in
      "${BASE_URL}"*) check_url_200 "$url" ;;
      *) fail "sitemap.xml contains unexpected host: ${url}" ;;
    esac
  done <<EOF_URLS
$urls
EOF_URLS
}

notify_failure() {
  [ "$failures" -eq 0 ] && return

  local text escaped
  text="竹田クリニック health-check failed (${failures}): ${failure_messages[*]}"
  if [ -n "$WEBHOOK_URL" ]; then
    escaped="$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    curl -fsS -X POST \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"${escaped}\"}" \
      "$WEBHOOK_URL" >/dev/null || true
  else
    printf 'TODO: set HEALTHCHECK_WEBHOOK_URL to notify Slack/Webhook. %s\n' "$text" >&2
  fi
}

main() {
  log "Starting health check for ${BASE_URL}"

  check_url_200 "${BASE_URL}/"
  check_url_200 "${WWW_URL}/"
  check_url_200 "http://${DOMAIN}/"
  check_url_200 "${BASE_URL}/sitemap.xml"
  check_url_200 "${BASE_URL}/robots.txt"
  check_url_200 "${BASE_URL}/kenshin.html"
  check_url_200 "${BASE_URL}/vaccination.html"
  check_url_200 "${BASE_URL}/recruit.html"
  check_url_200 "${BASE_URL}/assets/images/doctor-web.jpg"

  check_certificate
  check_canonical
  check_robots
  check_sitemap

  if [ "$failures" -gt 0 ]; then
    notify_failure
    log "Health check finished with ${failures} failure(s)"
    exit 1
  fi

  log "Health check passed"
}

main "$@"
