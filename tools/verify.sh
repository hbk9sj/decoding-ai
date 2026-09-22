#!/usr/bin/env bash
# The repo's verify command. Lints every post's copy, re-renders every carousel, re-runs
# every gate. Prints real counts. Exit 0 only if everything passes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
fails=0; carousels=0; texts=0
for d in render/fixtures/*/ posts/*/; do
  [ -f "${d}copy.json" ] || continue
  kind=$(jq -r '.kind' "${d}copy.json")
  if [ "$kind" = "carousel" ]; then
    out=$(node tools/render.mjs "${d%/}" 2>&1) || { echo "FAIL render ${d%/}"; echo "$out"; fails=$((fails+1)); continue; }
    echo "ok  ${d%/} — $out"; carousels=$((carousels+1))
  fi
  if [ "$kind" = "text" ] || [ -n "$(jq -r '.body // empty' "${d}copy.json")" ]; then
    out=$(node tools/lint_text.mjs "${d%/}" 2>&1) || { echo "FAIL lint ${d%/}"; echo "$out"; fails=$((fails+1)); continue; }
    echo "ok  ${d%/} — $out"; texts=$((texts+1))
  fi
done
bash -n tools/post.sh && bash -n tools/publish_job.sh && bash -n tools/buffer_query.sh || fails=$((fails+1))
echo "----"
echo "$carousels carousel(s) rendered and gated, $texts text body(ies) linted, $fails failure(s)"
[ $fails -eq 0 ]
