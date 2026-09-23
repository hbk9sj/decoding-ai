#!/usr/bin/env bash
# Send one message to the Decoding AI Slack channel. The message is read from stdin.
#   printf '%s\n' "text" | tools/slack.sh
# SLACK_WEBHOOK_URL is an incoming-webhook URL (an Actions secret; it is the credential).
# Unset: says so, raises an Actions warning, and exits 0 - an alert must never block a post.
# SLACK_DRY_RUN=1 prints the payload instead of sending it.
set -uo pipefail
msg="$(mktemp)"; trap 'rm -f "$msg"' EXIT
cat > "$msg"
payload=$(jq -n --rawfile t "$msg" '{text: ($t | sub("\n+$"; ""))}')
if [ "${SLACK_DRY_RUN:-}" = "1" ]; then printf '%s\n' "$payload"; exit 0; fi
if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "slack: not configured (set the SLACK_WEBHOOK_URL secret)"
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning::Slack alert not sent: SLACK_WEBHOOK_URL is not set"
  exit 0
fi
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL")
if [ "$code" = "200" ]; then echo "slack: sent"; else
  echo "slack: FAILED with HTTP $code"
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning::Slack alert failed with HTTP $code"
fi
exit 0
