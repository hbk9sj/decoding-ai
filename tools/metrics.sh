#!/usr/bin/env bash
# Daily: every post sent in the last 30 days, with Buffer's per-post metrics, into
# state/metrics.json - the file the routines read before choosing a format. Mondays (IST):
# a scoreboard of the last 7 days to Slack. Buffer gives no analytics for PDF carousels,
# so those rows point at state/manual.csv, which Suraj fills in from LinkedIn once a week.
#   tools/metrics.sh              (needs BUFFER_ACCESS_TOKEN, BUFFER_CHANNEL_ID, BUFFER_ORGANIZATION_ID)
#   METRICS_FORCE_SCOREBOARD=1    sends the scoreboard on any day
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
: "${BUFFER_ACCESS_TOKEN:?}" "${BUFFER_CHANNEL_ID:?}" "${BUFFER_ORGANIZATION_ID:?}"
REPO="${GH_REPO:-hbk9sj/decoding-ai}"
since=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
r=$(bash tools/buffer_query.sh 'query($o: OrganizationId!, $c: ChannelId!, $s: DateTime!){ posts(first:50, input:{organizationId:$o, filter:{channelIds:[$c], status:[sent], dueAt:{start:$s}}}){ edges { node { id sentAt text metricsUpdatedAt metrics { type value } } } } }' \
  "$(jq -cn --arg o "$BUFFER_ORGANIZATION_ID" --arg c "$BUFFER_CHANNEL_ID" --arg s "$since" '{o:$o,c:$c,s:$s}')")
jq -e '.data.posts.edges' <<<"$r" >/dev/null || { echo "Buffer query failed: $(jq -c '.errors' <<<"$r")" >&2; exit 1; }
jq --slurpfile done state/done.json --arg at "$(date -u +%FT%TZ)" '
  ($done[0] | to_entries | map({key: .value.post_id, value: {folder: .key, kind: .value.kind, pillar: .value.pillar}}) | from_entries) as $by
  | {generated_at: $at, posts: [.data.posts.edges[].node | {
      id, sent_at: .sentAt, folder: ($by[.id].folder // null), kind: ($by[.id].kind // null), pillar: ($by[.id].pillar // null),
      hook: (.text | split("\n")[0]), metrics_updated_at: .metricsUpdatedAt,
      metrics: ((.metrics // []) | map({key: .type, value: .value}) | from_entries)
    }] | sort_by(.sent_at)}' <<<"$r" > state/metrics.json
echo "metrics: $(jq '.posts | length' state/metrics.json) post(s) in the last 30 days -> state/metrics.json"

if [ "$(TZ=Asia/Kolkata date +%u)" = "1" ] || [ "${METRICS_FORCE_SCOREBOARD:-}" = "1" ]; then
  week=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
  { echo "Decoding AI - the week's scoreboard"
    jq -r --arg w "$week" '.posts[] | select(.sent_at >= $w) |
      "- \(.folder // .id) (\(.kind // "?"), \(.pillar // "?")): " +
      (if .kind == "carousel" then "impressions: ? (Buffer has no carousel analytics)"
       else "impressions \(.metrics.impressions // "?"), reactions \(.metrics.likes // "?"), comments \(.metrics.comments // "?"), follows \(.metrics.follows // "?")" end)' state/metrics.json
    echo
    echo "Add this week's carousel numbers and your follower count: https://github.com/$REPO/edit/main/state/manual.csv"
  } | bash tools/slack.sh
fi
