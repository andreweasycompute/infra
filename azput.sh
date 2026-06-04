#!/bin/bash
set -euo pipefail
shopt -s nullglob

IFACE=$(ip route | awk '/default/ {print $5; exit}')
MAC=$(<"/sys/class/net/$IFACE/address")
MAC=${MAC//:/-}

PREFIX="$(hostname)/${MAC}"

STORAGE_ACCOUNT="ezblob"
CONTAINER="ezlogs"
SAS_TOKEN="sp=w&st=2026-06-04T12:18:29Z&se=2026-06-11T20:33:29Z&sv=2026-02-06&sr=c&sig=6LyFZqV6Kw2AKcXW6vUl42iYzrX6FiuPJculF8yRJp4%3D"

upload_file() {
    local file="$1"
    local name
    name=$(basename "$file")

    status=$(curl -s -o /dev/null -w "%{http_code}" \
      -X PUT \
      -T "$file" \
      -H "x-ms-blob-type: BlockBlob" \
      "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${PREFIX}/${name}?${SAS_TOKEN}")

    if [[ "$status" == "201" ]]; then
        echo "Uploaded: $name"
    else
        echo "FAILED ($status): $file"
    fi
}

for file in ~/infra/test/fulltest_*; do
    upload_file "$file"
done

for file in ~/aginfra/infra/dc_power_test/*.csv; do
    upload_file "$file"
done
