#!/bin/bash

IFACE=$(ip route | awk '/default/ {print $5; exit}')
MAC=$(cat /sys/class/net/$IFACE/address)
MAC=${MAC//:/-}

PREFIX="$(hostname)/${MAC}"

STORAGE_ACCOUNT="ezblob"
CONTAINER="ezlogs"
SAS_TOKEN="sp=w&st=2026-06-04T12:18:29Z&se=2026-06-11T20:33:29Z&sv=2026-02-06&sr=c&sig=6LyFZqV6Kw2AKcXW6vUl42iYzrX6FiuPJculF8yRJp4%3D"

for file in ~/infra/test/fulltest_*; do
  name=$(basename "$file")

  curl -sS -X PUT \
    -T "$file" \
    -H "x-ms-blob-type: BlockBlob" \
    "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}//${PREFIX}/${name}?${SAS_TOKEN}"
done
