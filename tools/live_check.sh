#!/usr/bin/env bash
# Runs on every worker tick. For each post in state/done.json that has not yet gone live,
# ask Buffer: sent -> record live_url and sent_at, send the Live alert (the link, the second
# comment, the four-hour checklist); error -> record live_error, send the Failed alert.
#   tools/live_check.sh            (needs BUFFER_ACCESS_TOKEN; edits state/done.json)
# A post that went live more than 24 h ago is recorded without an alert (the backlog from
# before this check existed), so switching it on does not flood the channel.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
: "${BUFFER_ACCESS_TOKEN:?}"
run_url=""; [ -n "${GITHUB_RUN_ID:-}" ] && run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
now=$(date -u +%s); checked=0; live=0; failed=0

for k in $(jq -r 'to_entries[] | select(.value.post_id and (.value.live_url | not) and (.value.live_error | not)) | .key' state/done.json); do
  id=$(jq -r --arg k "$k" '.[$k].post_id' state/done.json)
  r=$(bash tools/buffer_query.sh 'query($id: PostId!){ post(input:{id:$id}){ status sentAt externalLink error { message } metadata { ... on LinkedInPostMetadata { linkAttachment { url } } } } }' "$(jq -cn --arg id "$id" '{id:$id}')" 2>&1) || { echo "$k: Buffer query failed: $r"; continue; }
  checked=$((checked+1))
  status=$(jq -r '.data.post.status // empty' <<<"$r")
  case "$status" in
    sent)
      ext=$(jq -r '.data.post.externalLink // empty' <<<"$r"); sent=$(jq -r '.data.post.sentAt // empty' <<<"$r")
      # externalLink has been seen as a URN; accept either form
      case "$ext" in http*) url="$ext" ;; urn:li:*) url="https://www.linkedin.com/feed/update/$ext/" ;; *) url="(Buffer gave no link: ${ext:-empty})" ;; esac
      jq --arg k "$k" --arg u "$url" --arg s "$sent" '.[$k].live_url = $u | .[$k].sent_at = $s' state/done.json > state/done.tmp && mv state/done.tmp state/done.json
      live=$((live+1))
      age=$(( now - $(python3 -c 'import sys,datetime as d; print(int(d.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "${sent:-1970-01-01T00:00:00Z}") ))
      if [ "$age" -gt 86400 ]; then echo "$k: live (recorded, older than 24 h, no alert)"; continue; fi
      second=$(jq -r '.second_comment // empty' "posts/$k/copy.json" 2>/dev/null)
      card=$(jq -r '.data.post.metadata.linkAttachment.url // empty' <<<"$r")
      { echo "Decoding AI - LIVE now: $k"
        echo "$url"
        [ -n "$card" ] && echo "WARNING: LinkedIn shows a link preview card ($card) - it costs about half the reach. Check the post."
        echo
        echo "Next 30 minutes: reply to every comment."
        if [ -n "$second" ]; then echo "Within 2 hours, post this as your own comment:"; echo "> $second"; fi
        echo "At 4-6 hours: repost it once."
        [ -n "$run_url" ] && echo "Run: $run_url"
      } | bash tools/slack.sh
      echo "$k: live $url" ;;
    error)
      msg=$(jq -r '.data.post.error.message // "no message"' <<<"$r")
      jq --arg k "$k" --arg m "$msg" '.[$k].live_error = $m' state/done.json > state/done.tmp && mv state/done.tmp state/done.json
      failed=$((failed+1))
      { echo "Decoding AI - FAILED to publish: $k"; echo "Buffer says: $msg"; echo "Fix it in Buffer, or re-queue the folder."; [ -n "$run_url" ] && echo "Run: $run_url"; } | bash tools/slack.sh
      echo "$k: error $msg" ;;
    *) echo "$k: ${status:-unknown} (waiting)" ;;
  esac
done
echo "live check: $checked checked, $live went live, $failed failed"
