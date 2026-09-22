#!/usr/bin/env bash
# Thin GraphQL client. tools/buffer_query.sh '<query>' '<json variables>'
set -euo pipefail
: "${BUFFER_ACCESS_TOKEN:?BUFFER_ACCESS_TOKEN not set}"
vars="${2:-}"; [ -n "$vars" ] || vars='{}'
curl -fsS https://api.buffer.com -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $BUFFER_ACCESS_TOKEN" \
  -d "$(jq -cn --arg q "${1:?query}" --argjson v "$vars" '{query:$q,variables:$v}')"
