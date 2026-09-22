#!/usr/bin/env bash
# Thin GraphQL client. tools/buffer_query.sh '<query>' '<json variables>'
set -euo pipefail
: "${BUFFER_ACCESS_TOKEN:?BUFFER_ACCESS_TOKEN not set}"
curl -fsS https://api.buffer.com -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $BUFFER_ACCESS_TOKEN" \
  -d "$(jq -cn --arg q "${1:?query}" --argjson v "${2:-{\}}" '{query:$q,variables:$v}')"
