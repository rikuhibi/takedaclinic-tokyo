#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C
export LANG=C

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 G-XXXXXXXXXX" >&2
  exit 2
fi

MEASUREMENT_ID="$1"

if [[ ! "$MEASUREMENT_ID" =~ ^G-[A-Z0-9]{6,20}$ ]]; then
  echo "Invalid GA4 Measurement ID: ${MEASUREMENT_ID}" >&2
  echo "Expected a value like G-XXXXXXXXXX." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/../dist/index.html" ]; then
  SITE_DIR="$(cd "${SCRIPT_DIR}/../dist" && pwd)"
else
  SITE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

FILES=(
  "index.html"
  "kenshin.html"
  "vaccination.html"
  "recruit.html"
  "404.html"
)

GA4_SNIPPET="$(cat <<HTML
<!-- GA4_BEGIN -->
<script async src="https://www.googletagmanager.com/gtag/js?id=${MEASUREMENT_ID}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag("js", new Date());
  gtag("config", "${MEASUREMENT_ID}");
</script>
<!-- GA4_END -->
HTML
)"

export GA4_SNIPPET

for file in "${FILES[@]}"; do
  path="${SITE_DIR}/${file}"
  if [ ! -f "$path" ]; then
    echo "Missing expected HTML file: ${path}" >&2
    exit 1
  fi

  if ! grep -q '<!-- GA4_BEGIN -->' "$path"; then
    echo "GA4 placeholder block not found in ${path}" >&2
    exit 1
  fi

  perl -0pi -e 'BEGIN { $snippet = $ENV{"GA4_SNIPPET"}; } s/<!-- GA4_BEGIN -->.*?<!-- GA4_END -->/$snippet/s' "$path"
  echo "Updated ${path}"
done

echo "GA4 injection complete for ${MEASUREMENT_ID}."
