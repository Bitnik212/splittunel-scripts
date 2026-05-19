#!/bin/bash

echo "Building RU ip list without blocked ips"
#python3 ru_without_antifilter.py > ru.ips

FILE="ru.ips"

echo "Load RU ips"
while IFS= read -r ip; do
    # remove trailing comma
    ip="${ip%,}"

    # skip empty lines and comments
    [[ -z "$ip" || "$ip" =~ ^# ]] && continue

    echo "Adding $ip"
    ipset add ru "$ip" -exist
done < "$FILE"

echo "Done"
