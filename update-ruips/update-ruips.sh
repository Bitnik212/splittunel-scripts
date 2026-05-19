#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://functions.yandexcloud.net/d4e7md80q0icmfckbi5u"
ASN_FILE="${1:-asn.txt}"
OUTPUT_FILE="ru.ips"
TMP_FILE="${OUTPUT_FILE}.tmp"

INSECURE="true"

CONNECT_TIMEOUT=10
MAX_TIME=300

QUERY="insecure=${INSECURE}"

while IFS= read -r line; do
    asn="$(echo "$line" | xargs)"

    [[ -z "$asn" || "$asn" =~ ^# ]] && continue

    if [[ ! "$asn" =~ ^AS ]]; then
        asn="AS$asn"
    fi

    QUERY+="&exclude_asn=${asn}"
done < "$ASN_FILE"

URL="${BASE_URL}?${QUERY}"

echo "Requesting:"
echo "$URL"
echo "Saving to ${OUTPUT_FILE}"
echo

# write to temp file first
curl \
  --connect-timeout "$CONNECT_TIMEOUT" \
  --max-time "$MAX_TIME" \
  --retry 3 \
  --retry-delay 2 \
  --retry-max-time "$MAX_TIME" \
  --fail \
  --show-error \
  --silent \
  "$URL" \
  -o "$TMP_FILE"

# replace only if successful
mv "$TMP_FILE" "$OUTPUT_FILE"

echo "Done ✅"
