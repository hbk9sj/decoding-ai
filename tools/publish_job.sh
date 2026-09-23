#!/usr/bin/env bash
# Process one post folder end to end: gate it, queue it in Buffer, write the record, alert.
#   tools/publish_job.sh posts/<folder>
# Exit 0 only when gate and post both succeeded; run.md is written either way, and it
# carries the first-four-hours checklist, which is the part no pipeline can do.
# job.json {"smoke": true} queues a draft, reads it back, deletes it, and records nothing
# in state/done.json - a live end-to-end check that never reaches LinkedIn.
set -uo pipefail
f="${1:?posts/<folder>}"; name=$(basename "$f"); ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f "$f/copy.json" ] || { echo "no $f/copy.json"; exit 1; }
kind=$(jq -r '.kind' "$f/copy.json"); pillar=$(jq -r '.pillar // "-"' "$f/copy.json")
draft=$(jq -r '.draft // false' "$f/job.json" 2>/dev/null || echo false)
smoke=$(jq -r '.smoke // false' "$f/job.json" 2>/dev/null || echo false)
[ "$smoke" = "true" ] && draft=true
log="$f/run.md"; gate_ok=0; post_ok=0
run_url=""; [ -n "${GITHUB_RUN_ID:-}" ] && run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
ist() { python3 -c 'import sys,datetime as d,zoneinfo as z; t=d.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).astimezone(z.ZoneInfo("Asia/Kolkata")); print(t.strftime("%a %d %b, %H:%M IST"))' "$1" 2>/dev/null || echo "$1"; }

# 1. gate: render (a carousel's pages, a text post's card) and the text contract
gate_out=$(node tools/render.mjs "$f" 2>&1); [ $? -eq 0 ] && gate_ok=1
text_out=$(node tools/lint_text.mjs "$f" 2>&1) || gate_ok=0
gate_out="$gate_out
$text_out"

# 2. queue
post_out="skipped"
if [ $gate_ok -eq 1 ]; then
  flag=""; [ "$draft" = "true" ] && flag="--draft"
  post_out=$(bash tools/post.sh "$f" $flag 2>&1) && post_ok=1
fi
id=""; due=""
if [ $post_ok -eq 1 ]; then
  id=$(printf '%s\n' "$post_out" | tail -1)
  due=$(printf '%s\n' "$post_out" | tail -2 | head -1 | jq -r '.dueAt // empty' 2>/dev/null)
fi

# 3. smoke: prove the delete, so the check leaves nothing behind
smoke_out=""
if [ "$smoke" = "true" ] && [ -n "$id" ]; then
  del=$(bash tools/buffer_query.sh 'mutation($id: PostId!){ deletePost(input:{id:$id}){ ... on DeletePostSuccess { id } ... on VoidMutationError { message } } }' "$(jq -cn --arg id "$id" '{id:$id}')" 2>&1)
  again=$(bash tools/buffer_query.sh 'query($id: PostId!){ post(input:{id:$id}){ id status } }' "$(jq -cn --arg id "$id" '{id:$id}')" 2>&1)
  if jq -e '.data.deletePost.id' <<<"$del" >/dev/null 2>&1 && ! jq -e '.data.post.id' <<<"$again" >/dev/null 2>&1; then
    smoke_out="smoke: draft $id read back, deleted, and no longer found"
  else
    smoke_out="smoke: DELETE NOT CONFIRMED for $id - remove the draft in Buffer by hand
$del
$again"; post_ok=0
  fi
fi

# 4. the record
second=$(jq -r '.second_comment // empty' "$f/copy.json")
{ printf '# run %s - %s\n\n' "$name" "$(date -u +%FT%TZ)"
  printf 'kind: %s - pillar: %s\n\n' "$kind" "$pillar"
  printf 'gate: %s\n```\n%s\n```\n\n' "$([ $gate_ok -eq 1 ] && echo pass || echo FAILED)" "$gate_out"
  printf 'post: %s\n```\n%s\n```\n' "$([ $post_ok -eq 1 ] && echo queued || echo FAILED)" "$post_out"
  [ -n "$smoke_out" ] && printf '\n```\n%s\n```\n' "$smoke_out"
  [ -n "$due" ] && printf '\ngoes live: %s (%s)\n' "$(ist "$due")" "$due"
  if [ $post_ok -eq 1 ] && [ "$smoke" != "true" ]; then cat <<'NOTE'

## The four hours after it goes live (this is the 10-14x, and only a person can do it)
- The hour before: leave a real 15+ word comment on five posts in the same topic
  (roster picks, when roster.md is approved, arrive in the Slack alert).
- First 30 minutes: reply to every comment. One reply now beats ten tomorrow.
- Within 2 hours: post the second comment below, by hand, as yourself.
- At 4-6 hours: repost it yourself, once. Never twice.
NOTE
    [ -n "$second" ] && printf '\nsecond comment:\n\n> %s\n' "$second"
  fi
  [ -n "$run_url" ] && printf '\nworkflow: %s\n' "$run_url"
} > "$log"

if [ -n "$id" ] && [ "$smoke" != "true" ]; then
  jq --arg k "$name" --arg id "$id" --arg t "$(jq -r .topic "$f/copy.json")" --arg p "$pillar" \
     --arg tpl "$(jq -r '.template // "-"' "$f/copy.json")" --arg hook "$(jq -r '.body' "$f/copy.json" | head -1)" \
     --arg d "$(date -u +%F)" --arg k2 "$kind" --arg due "$due" \
     '.[$k] = {topic:$t, pillar:$p, kind:$k2, template:$tpl, hook:$hook, post_id:$id, date:$d, due_at:$due}' state/done.json > state/done.tmp && mv state/done.tmp state/done.json
fi

# 5. the alert: queued (with what to do before it goes live) or failed (with why)
if [ $gate_ok -eq 1 ] && [ $post_ok -eq 1 ]; then
  picks="roster not approved yet - pick five posts from people you follow"
  if grep -q '^status: approved' roster.md 2>/dev/null && [ "$(jq '.roster_picks // [] | length' "$f/copy.json")" -gt 0 ]; then
    picks=$(jq -r '.roster_picks[] | "- \(.author): \(.url)\n  angle: \(.angle)"' "$f/copy.json")
  fi
  { if [ "$smoke" = "true" ]; then echo "Decoding AI - smoke check passed: $name"; echo "$smoke_out"
    else
      echo "Decoding AI - queued: $name ($kind, $pillar)"
      [ -n "$due" ] && echo "Goes live: $(ist "$due")"
      printf '%s\n' "$post_out" | grep '^spaced:' || true
      echo; jq -r '.body' "$f/copy.json" | head -c 300; echo "..."
      echo; echo "The hour before it goes live, comment on these (15+ words each):"; echo "$picks"
    fi
    [ -n "$run_url" ] && echo "Run: $run_url"
  } | bash tools/slack.sh
else
  { echo "Decoding AI - FAILED: $name ($kind, $pillar)"
    echo "$([ $gate_ok -eq 1 ] && echo 'gate passed, Buffer step failed:' || echo 'gate failed:')"
    printf '%s\n%s\n%s\n' "$([ $gate_ok -eq 1 ] || echo "$gate_out")" "$([ $gate_ok -eq 1 ] && echo "$post_out")" "$smoke_out" | grep -v '^$' | tail -15
    [ -n "$run_url" ] && echo "Run: $run_url"
  } | bash tools/slack.sh
fi

echo "$name gate=$gate_ok post=$post_ok ${id:+buffer=$id}"
[ $gate_ok -eq 1 ] && [ $post_ok -eq 1 ]
