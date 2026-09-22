#!/usr/bin/env bash
# Process one post folder end to end: gate it, queue it in Buffer, write the record.
#   tools/publish_job.sh posts/<folder>
# Exit 0 only when gate and post both succeeded; run.md is written either way, and it
# carries the first-four-hours checklist, which is the part no pipeline can do.
set -uo pipefail
f="${1:?posts/<folder>}"; name=$(basename "$f"); ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f "$f/copy.json" ] || { echo "no $f/copy.json"; exit 1; }
kind=$(jq -r '.kind' "$f/copy.json"); draft=$(jq -r '.draft // false' "$f/job.json" 2>/dev/null || echo false)
log="$f/run.md"; gate_ok=0; post_ok=0

if [ "$kind" = "carousel" ]; then
  gate_out=$(node tools/render.mjs "$f" 2>&1); [ $? -eq 0 ] && gate_ok=1
  text_out=$(node tools/lint_text.mjs "$f" 2>&1); [ $? -ne 0 ] && { gate_ok=0; gate_out="$gate_out
$text_out"; } || gate_out="$gate_out
$text_out"
else
  gate_out=$(node tools/lint_text.mjs "$f" 2>&1); [ $? -eq 0 ] && gate_ok=1
fi

post_out="skipped"
if [ $gate_ok -eq 1 ]; then
  flag=""; [ "$draft" = "true" ] && flag="--draft"
  post_out=$(bash tools/post.sh "$f" $flag 2>&1) && post_ok=1
fi
id=""; [ $post_ok -eq 1 ] && id=$(printf '%s\n' "$post_out" | tail -1)

{ printf '# run %s - %s\n\n' "$name" "$(date -u +%FT%TZ)"
  printf 'kind: %s - pillar: %s\n\n' "$kind" "$(jq -r '.pillar // "-"' "$f/copy.json")"
  printf 'gate: %s\n```\n%s\n```\n\n' "$([ $gate_ok -eq 1 ] && echo pass || echo FAILED)" "$gate_out"
  printf 'post: %s\n```\n%s\n```\n' "$([ $post_ok -eq 1 ] && echo queued || echo FAILED)" "$post_out"
  if [ $post_ok -eq 1 ]; then cat <<'NOTE'

## The four hours after it goes live (this is the 10-14x, and only a person can do it)
- Before it publishes: leave a real 15+ word comment on five posts in the same topic.
- First 30 minutes: reply to every comment. One reply now beats ten tomorrow.
- Within 2 hours: add two comments of your own with context the post left out.
- At 4-6 hours: repost it yourself, once. Never twice.
NOTE
  fi
  [ -n "${GITHUB_RUN_ID:-}" ] && printf '\nworkflow: %s/%s/actions/runs/%s\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
} > "$log"

if [ -n "$id" ]; then
  jq --arg k "$name" --arg id "$id" --arg t "$(jq -r .topic "$f/copy.json")" --arg p "$(jq -r '.pillar' "$f/copy.json")" \
     --arg tpl "$(jq -r '.template // "-"' "$f/copy.json")" --arg hook "$(jq -r '.body' "$f/copy.json" | head -1)" \
     --arg d "$(date -u +%F)" --arg k2 "$kind" \
     '.[$k] = {topic:$t, pillar:$p, kind:$k2, template:$tpl, hook:$hook, post_id:$id, date:$d}' state/done.json > state/done.tmp && mv state/done.tmp state/done.json
fi
echo "$name gate=$gate_ok post=$post_ok ${id:+buffer=$id}"
[ $gate_ok -eq 1 ] && [ $post_ok -eq 1 ]
