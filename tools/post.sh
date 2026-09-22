#!/usr/bin/env bash
# Publish one gated post to the Decoding AI LinkedIn channel through Buffer.
#   tools/post.sh posts/<folder> [--draft]
# Needs BUFFER_ACCESS_TOKEN, BUFFER_CHANNEL_ID, BUFFER_ORGANIZATION_ID.
# Carousels: the PDF and its thumbnail are published to the repo's "assets" branch first
# (never main — main only moves through a reviewed PR) and must answer 200 before Buffer
# sees them, because Buffer stores the URL and fetches it at publish time.
# Prints the Buffer post id on success. Refuses, before calling Buffer, on a failed gate,
# a missing file, a disconnected channel, or a full scheduled-post queue.
set -euo pipefail
folder="${1:?posts/<folder>}"; mode="${2:-}"
: "${BUFFER_ACCESS_TOKEN:?}" "${BUFFER_CHANNEL_ID:?}" "${BUFFER_ORGANIZATION_ID:?}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; dir="$ROOT/$folder"; name="$(basename "$folder")"
REPO="${GH_REPO:-hbk9sj/decoding-ai}"; BRANCH="assets"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
q() { bash "$ROOT/tools/buffer_query.sh" "$1" "${2:-}"; }

kind=$(jq -r '.kind' "$dir/copy.json")

# 0. the channel must be connected, or Buffer fails silently at publish time
ch=$(q 'query($id: ChannelId!){ channel(input:{id:$id}){ isDisconnected isLocked service } }' "$(jq -cn --arg id "$BUFFER_CHANNEL_ID" '{id:$id}')")
[ "$(jq -r '.data.channel.isDisconnected' <<<"$ch")" = "false" ] || { echo "Buffer channel is disconnected - reconnect it before posting" >&2; exit 2; }
[ "$(jq -r '.data.channel.service' <<<"$ch")" = "linkedin" ] || { echo "channel is not the LinkedIn one" >&2; exit 2; }

# 1. the scheduled-post cap is shared with every other channel on this Buffer plan
cap=$(q 'query{ account { organizations { id limits { scheduledPosts } } } }' \
  | jq -r --arg o "$BUFFER_ORGANIZATION_ID" '.data.account.organizations[] | select(.id == $o) | .limits.scheduledPosts')
pending=$(q 'query($o: OrganizationId!){ posts(first:50, input:{organizationId:$o, filter:{status:[scheduled,needs_approval,draft]}}){ edges { node { id } } } }' \
  "$(jq -cn --arg o "$BUFFER_ORGANIZATION_ID" '{o:$o}')" | jq '.data.posts.edges | length')
if [ "$pending" -ge "${cap:-10}" ]; then
  echo "Buffer holds $pending pending posts and the plan cap is $cap - not queueing another" >&2; exit 2
fi
[ "$pending" -ge $(( ${cap:-10} - 1 )) ] && echo "warning: only one slot left on this Buffer plan ($pending/$cap used, shared with the other channels)" >&2

# 2. assets
assets='[]'
if [ "$kind" = "carousel" ]; then
  clean=$(jq '[.pages[] | select(.problems | length == 0)] | length' "$dir/gate.json")
  total=$(jq '.pages | length' "$dir/gate.json")
  [ "$clean" = "$total" ] || { echo "gate.json reports $clean/$total clean pages - not posting" >&2; exit 2; }
  [ -s "$dir/carousel.pdf" ] && [ -s "$dir/thumb.png" ] || { echo "carousel.pdf or thumb.png missing - run tools/render.mjs" >&2; exit 2; }
  work="$(mktemp -d)"
  git clone -q --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$work" 2>/dev/null \
    || { git clone -q --depth 1 "https://github.com/$REPO.git" "$work"; git -C "$work" switch -q --orphan "$BRANCH"; git -C "$work" rm -rqf . 2>/dev/null || true; }
  mkdir -p "$work/$folder"; cp "$dir/carousel.pdf" "$dir/thumb.png" "$work/$folder/"
  ( cd "$work"
    git config user.name decoding-ai; git config user.email decoding-ai@users.noreply.github.com
    git add "$folder/carousel.pdf" "$folder/thumb.png"
    git diff --cached --quiet || git commit -qm "assets: $name"
    for try in 1 2 3 4 5; do git push -q origin "HEAD:$BRANCH" && break; git fetch -q origin "$BRANCH" && git rebase -q "origin/$BRANCH" || true
      [ "$try" = 5 ] && { echo "asset push failed" >&2; exit 2; }; sleep 5; done )
  rm -rf "$work"
  pdf_url="$RAW/$folder/carousel.pdf"; thumb_url="$RAW/$folder/thumb.png"
  # Buffer stores the URL and fetches it at publish time, so it must resolve first.
  # raw.githubusercontent serves a PDF as application/octet-stream; Buffer accepts that.
  wait_public() { # wait_public <url> <content-type regex>
    for try in $(seq 1 15); do
      curl -fsSI "$1" 2>/dev/null | grep -qiE "^content-type: $2" && return 0
      sleep 6
    done
    echo "not public after 90 s: $1" >&2; return 1
  }
  wait_public "$pdf_url" 'application/(pdf|octet-stream)' || exit 2
  wait_public "$thumb_url" 'image/png' || exit 2
  assets=$(jq -cn --arg u "$pdf_url" --arg t "$(jq -r .title "$dir/copy.json")" --arg th "$thumb_url" \
    '[{document:{url:$u, title:$t, thumbnailUrl:$th}}]')
fi

# 3. the post itself
text=$(jq -r '.body' "$dir/copy.json")
first_comment=$(jq -r '.first_comment // empty' "$dir/copy.json")
due=$(jq -r '.due_at // empty' "$dir/job.json" 2>/dev/null)
[ -n "$due" ] || due=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)+d.timedelta(minutes=6)).strftime("%Y-%m-%dT%H:%M:00Z"))')
# LinkedIn channels refuse schedulingType "notification" ("Use automatic scheduling
# instead" - Buffer, checked 22 Sep 2026), so the human gate is a draft, not a reminder.
if [ "$mode" = "--draft" ]; then extra='{"saveToDraft":true,"schedulingType":"automatic","mode":"addToQueue"}'
else extra=$(jq -cn --arg due "$due" '{schedulingType:"automatic", mode:"customScheduled", dueAt:$due}'); fi
meta=$(jq -cn --arg fc "$first_comment" '{linkedin: (if $fc == "" then {} else {firstComment:$fc} end)}')
vars=$(jq -cn --arg ch "$BUFFER_CHANNEL_ID" --arg text "$text" --argjson assets "$assets" --argjson meta "$meta" --argjson extra "$extra" \
  '{input: ({channelId:$ch, text:$text, assets:$assets, metadata:$meta} + $extra)}')
mutation='mutation($input: CreatePostInput!){ createPost(input:$input){ ... on PostActionSuccess { post { id status dueAt } } ... on MutationError { message } } }'
resp=$(q "$mutation" "$vars")
# Buffer's Free plan refuses a LinkedIn first comment. The source link must never go in the
# body (~60 % of reach), so the post goes out without it and run.md hands the comment to a
# human to paste - which is the golden hour they should be in anyway.
if jq -e '.data.createPost.message // "" | test("first comment requires a paid plan"; "i")' <<<"$resp" >/dev/null; then
  echo "note: this Buffer plan cannot set a LinkedIn first comment - posting without it" >&2
  echo "PASTE THIS AS THE FIRST COMMENT: $first_comment" >&2
  vars=$(jq -cn --arg ch "$BUFFER_CHANNEL_ID" --arg text "$text" --argjson assets "$assets" --argjson extra "$extra" \
    '{input: ({channelId:$ch, text:$text, assets:$assets} + $extra)}')
  resp=$(q "$mutation" "$vars")
fi
id=$(jq -r '.data.createPost.post.id // empty' <<<"$resp")
[ -n "$id" ] || { echo "Buffer refused: $(jq -c '.data.createPost.message // .errors' <<<"$resp")" >&2; exit 1; }
jq -c '.data.createPost.post' <<<"$resp"
echo "$id"
