#!/usr/bin/env bash

URL="https://functions.yandexcloud.net/d4er6kvdg57fodc76j7g"
INPUT_FILE="custom_domains.txt"
TMP_FILE="responses.jsonl"
OUTPUT_IPS="ru.ips"

THREADS=10

> "$TMP_FILE"
#> "$OUTPUT_IPS"

cat "$INPUT_FILE" \
  | sort -u \
  | grep -v '^$' \
  | xargs -P "$THREADS" -I {} bash -c '
    domain="{}"

    echo "[*] $domain"

    response=$(curl --silent \
      --max-time 30 \
      --location "'"$URL"'" \
      --header "Content-Type: application/json" \
      --data "{\"domain\": \"$domain\"}")

    if [ $? -eq 0 ] && [ -n "$response" ]; then
      echo "$response" >> "'"$TMP_FILE"'"
    else
      echo "{\"domain\":\"$domain\",\"error\":\"failed\"}" >> "'"$TMP_FILE"'"
    fi
'

# extract all IPs
cat "$TMP_FILE" \
  | jq -r '.all_ips[]?' \
  | sort -u \
  >> "$OUTPUT_IPS"

echo "✅ Done"
echo "IPs saved to: $OUTPUT_IPS"
echo "Raw responses: $TMP_FILE"

