#!/usr/bin/env bash
# Publish one gated post to the Decoding AI LinkedIn channel through Buffer.
#   tools/post.sh posts/<folder> [--draft]
# Needs BUFFER_ACCESS_TOKEN, BUFFER_CHANNEL_ID, BUFFER_ORGANIZATION_ID.
# Assets (a carousel's PDF and thumbnail, a text post's card) are published to the repo's "assets" branch first
# (never main — main only moves through a reviewed PR) and must answer 200 before Buffer
# sees them, because Buffer stores the URL and fetches it at publish time.
# Prints the Buffer post id on success. Refuses, before calling Buffer, on a failed gate,
# a missing file, a disconnected channel, link shortening switched on, a full scheduled-post
# queue, or no clear day within a week. After Buffer accepts the post it is read back; if
# Buffer changed the text or attached a link card, the post is deleted and this fails.
set -euo pipefail
folder="${1:?posts/<folder>}"; mode="${2:-}"
: "${BUFFER_ACCESS_TOKEN:?}" "${BUFFER_CHANNEL_ID:?}" "${BUFFER_ORGANIZATION_ID:?}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; dir="$ROOT/$folder"; name="$(basename "$folder")"
REPO="${GH_REPO:-hbk9sj/decoding-ai}"; BRANCH="assets"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
q() { bash "$ROOT/tools/buffer_query.sh" "$1" "${2:-}"; }

kind=$(jq -r '.kind' "$dir/copy.json")

# 0. the channel must be connected, or Buffer fails silently at publish time
ch=$(q 'query($id: ChannelId!){ channel(input:{id:$id}){ isDisconnected isLocked service linkShortening { isEnabled } } }' "$(jq -cn --arg id "$BUFFER_CHANNEL_ID" '{id:$id}')")
[ "$(jq -r '.data.channel.isDisconnected' <<<"$ch")" = "false" ] || { echo "Buffer channel is disconnected - reconnect it before posting" >&2; exit 2; }
[ "$(jq -r '.data.channel.service' <<<"$ch")" = "linkedin" ] || { echo "channel is not the LinkedIn one" >&2; exit 2; }
# the source URL is the post's proof; a shortener would swap it for a buff.ly link
shorten=$(jq -r '.data.channel.linkShortening.isEnabled' <<<"$ch")
echo "link shortening: $shorten" >&2
[ "$shorten" = "false" ] || { echo "Buffer link shortening is on for this channel - it would replace the source URL. Switch it off in the channel's settings in Buffer." >&2; exit 2; }

# 1. the scheduled-post cap is PER CHANNEL, not per account - checked 22 Sep 2026 by
# queueing an 11th post while the account already held 10 across its channels, which
# Buffer accepted. So count only this channel's pending posts.
cap=$(q 'query{ account { organizations { id limits { scheduledPosts } } } }' \
  | jq -r --arg o "$BUFFER_ORGANIZATION_ID" '.data.account.organizations[] | select(.id == $o) | .limits.scheduledPosts')
pending=$(q 'query($o: OrganizationId!, $c: ChannelId!){ posts(first:50, input:{organizationId:$o, filter:{channelIds:[$c], status:[scheduled,needs_approval,draft]}}){ edges { node { id } } } }' \
  "$(jq -cn --arg o "$BUFFER_ORGANIZATION_ID" --arg c "$BUFFER_CHANNEL_ID" '{o:$o,c:$c}')" | jq '.data.posts.edges | length')
if [ "$pending" -ge "${cap:-10}" ]; then
  echo "this channel already holds $pending pending posts and the cap is $cap - not queueing another" >&2; exit 2
fi

# 2. assets: which files this kind ships, gated first
case "$kind" in
  carousel) files="carousel.pdf thumb.png" ;;
  text) files="card.png" ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac
clean=$(jq '[.pages[] | select(.problems | length == 0)] | length' "$dir/gate.json" 2>/dev/null || echo 0)
total=$(jq '.pages | length' "$dir/gate.json" 2>/dev/null || echo 0)
[ "$total" -gt 0 ] && [ "$clean" = "$total" ] || { echo "gate.json reports $clean/$total clean pages - not posting" >&2; exit 2; }
for x in $files; do [ -s "$dir/$x" ] || { echo "$x missing - run tools/render.mjs" >&2; exit 2; }; done
# In CI there is no credential helper, so the token has to be in the remote URL.
# It never reaches the log: the URL is only ever passed to git, and the clone is deleted.
remote="https://github.com/$REPO.git"
[ -n "${GH_TOKEN:-}" ] && remote="https://x-access-token:${GH_TOKEN}@github.com/$REPO.git"
work="$(mktemp -d)"
git clone -q --depth 1 --branch "$BRANCH" "$remote" "$work" 2>/dev/null \
  || { git clone -q --depth 1 "$remote" "$work"; git -C "$work" switch -q --orphan "$BRANCH"; git -C "$work" rm -rqf . 2>/dev/null || true; }
mkdir -p "$work/$folder"; for x in $files; do cp "$dir/$x" "$work/$folder/"; done
( cd "$work"
  git config user.name decoding-ai; git config user.email decoding-ai@users.noreply.github.com
  for x in $files; do git add "$folder/$x"; done
  git diff --cached --quiet || git commit -qm "assets: $name"
  for try in 1 2 3 4 5; do git push -q origin "HEAD:$BRANCH" 2>/dev/null && break; git fetch -q origin "$BRANCH" && git rebase -q "origin/$BRANCH" || true
    [ "$try" = 5 ] && { echo "asset push failed" >&2; exit 2; }; sleep 5; done )
rm -rf "$work"
# Buffer stores the URL and fetches it at publish time, so it must resolve first.
# raw.githubusercontent serves a PDF as application/octet-stream; Buffer accepts that.
wait_public() { # wait_public <url> <content-type regex>
  for try in $(seq 1 15); do
    curl -fsSI "$1" 2>/dev/null | grep -qiE "^content-type: $2" && return 0
    sleep 6
  done
  echo "not public after 90 s: $1" >&2; return 1
}
if [ "$kind" = "carousel" ]; then
  pdf_url="$RAW/$folder/carousel.pdf"; thumb_url="$RAW/$folder/thumb.png"
  wait_public "$pdf_url" 'application/(pdf|octet-stream)' || exit 2
  wait_public "$thumb_url" 'image/png' || exit 2
  assets=$(jq -cn --arg u "$pdf_url" --arg t "$(jq -r .title "$dir/copy.json")" --arg th "$thumb_url" \
    '[{document:{url:$u, title:$t, thumbnailUrl:$th}}]')
else
  card_url="$RAW/$folder/card.png"
  wait_public "$card_url" 'image/png' || exit 2
  # the image shape proven live in something-new/tools/post.sh; altText is required by Buffer
  assets=$(jq -cn --arg u "$card_url" --arg alt "$(jq -r '.card.alt' "$dir/copy.json")" '[{image:{url:$u, metadata:{altText:$alt}}}]')
fi

# 3. the post itself. No metadata: no first comment (Buffer Free refuses it; LinkedIn
# hides link comments) and never a link attachment (a preview card halves reach).
text=$(jq -r '.body' "$dir/copy.json")
src=$(jq -r '.source.url' "$dir/copy.json")
due=$(jq -r '.due_at // empty' "$dir/job.json" 2>/dev/null)
[ -n "$due" ] || due=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)+d.timedelta(minutes=6)).strftime("%Y-%m-%dT%H:%M:00Z"))')
# LinkedIn channels refuse schedulingType "notification" ("Use automatic scheduling
# instead" - Buffer, checked 22 Sep 2026), so the human gate is a draft, not a reminder.
if [ "$mode" = "--draft" ]; then extra='{"saveToDraft":true,"schedulingType":"automatic","mode":"addToQueue"}'
else
  # 24 h between posts: every scheduled or sent post from a day before to 8 days after
  span=$(python3 -c 'import sys,datetime as d; t=d.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")); f=lambda x: x.strftime("%Y-%m-%dT%H:%M:%SZ"); print(f(t-d.timedelta(hours=24)), f(t+d.timedelta(days=8)))' "$due")
  taken=$(q 'query($o: OrganizationId!, $c: ChannelId!, $s: DateTime!, $e: DateTime!){ posts(first:50, input:{organizationId:$o, filter:{channelIds:[$c], status:[scheduled,needs_approval,sending,sent], dueAt:{start:$s, end:$e}}}){ edges { node { dueAt } } } }' \
    "$(jq -cn --arg o "$BUFFER_ORGANIZATION_ID" --arg c "$BUFFER_CHANNEL_ID" --arg s "${span% *}" --arg e "${span#* }" '{o:$o,c:$c,s:$s,e:$e}')" \
    | jq -c '[.data.posts.edges[].node.dueAt | select(. != null)]')
  due=$(node "$ROOT/tools/spacing.mjs" "$due" "$taken") || { echo "spacing: no clear day within 7 days of the slot" >&2; exit 2; }
  extra=$(jq -cn --arg due "$due" '{schedulingType:"automatic", mode:"customScheduled", dueAt:$due}')
fi
vars=$(jq -cn --arg ch "$BUFFER_CHANNEL_ID" --arg text "$text" --argjson assets "$assets" --argjson extra "$extra" \
  '{input: ({channelId:$ch, text:$text, assets:$assets} + $extra)}')
mutation='mutation($input: CreatePostInput!){ createPost(input:$input){ ... on PostActionSuccess { post { id status dueAt } } ... on MutationError { message } } }'
resp=$(q "$mutation" "$vars")
id=$(jq -r '.data.createPost.post.id // empty' <<<"$resp")
[ -n "$id" ] || { echo "Buffer refused: $(jq -c '.data.createPost.message // .errors' <<<"$resp")" >&2; exit 1; }

# 4. read it back: what Buffer stored is what LinkedIn gets
back=$(q 'query($id: PostId!){ post(input:{id:$id}){ id status dueAt text assets { __typename ... on ImageAsset { source image { altText } } ... on DocumentAsset { source } } metadata { ... on LinkedInPostMetadata { firstComment linkAttachment { url } } } } }' "$(jq -cn --arg id "$id" '{id:$id}')")
wrong=""
# a read-back that could not run is a refusal, not a pass: nothing was checked
jq -e '.data.post.id' <<<"$back" >/dev/null 2>&1 || wrong="; the read-back query failed: $(jq -c '.errors // .' <<<"$back" 2>/dev/null | head -c 400)"
[ -n "$wrong" ] || [ "$(jq -r '.data.post.text' <<<"$back")" = "$text" ] || wrong="$wrong; the stored text differs from copy.json"
[ -n "$wrong" ] || jq -r '.data.post.text' <<<"$back" | tail -1 | grep -qF -- "$src" || wrong="$wrong; the source URL is not on the stored last line"
[ "$(jq -r '.data.post.metadata.linkAttachment.url // empty' <<<"$back")" = "" ] || wrong="$wrong; Buffer attached a link card"
[ "$(jq -r '.data.post.metadata.firstComment // empty' <<<"$back")" = "" ] || wrong="$wrong; a first comment is set"
if [ "$kind" = "text" ] && ! grep -q 'read-back query failed' <<<"$wrong"; then
  [ "$(jq -r '[.data.post.assets[] | select(.__typename == "ImageAsset")] | length' <<<"$back")" = "1" ] || wrong="$wrong; no image asset"
  [ "$(jq -r '[.data.post.assets[] | select(.__typename == "ImageAsset")][0].image.altText // empty' <<<"$back")" = "$(jq -r '.card.alt' "$dir/copy.json")" ] || wrong="$wrong; the image alt text did not survive"
fi
if [ -n "$wrong" ]; then
  q 'mutation($id: PostId!){ deletePost(input:{id:$id}){ ... on DeletePostSuccess { id } ... on VoidMutationError { message } } }' "$(jq -cn --arg id "$id" '{id:$id}')" >/dev/null || true
  echo "read-back failed${wrong} - post $id deleted, nothing will publish" >&2; exit 1
fi
echo "read-back ok: text exact, source URL last, no link card, no first comment$([ "$kind" = text ] && echo ', image with alt text')" >&2
jq -c '.data.createPost.post' <<<"$resp"
echo "$id"
