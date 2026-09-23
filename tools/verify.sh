#!/usr/bin/env bash
# The repo's verify command. Renders and gates every fixture and every post not yet
# published, lints every body, proves each refusal fixture is refused for its own reason,
# runs the unit tests and syntax-checks the scripts. Prints real counts. Exit 0 only if
# everything passes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
fails=0; carousels=0; cards=0; texts=0; skipped=0; refused=0; nref=0
for d in render/fixtures/*/ posts/*/; do
  [ -f "${d}copy.json" ] || continue
  # a published post is history: its copy was checked under the rules of its day
  case "$d" in posts/*) [ -f "${d}run.md" ] && { skipped=$((skipped+1)); continue; } ;; esac
  kind=$(jq -r '.kind' "${d}copy.json")
  if [ "$kind" = "carousel" ] || [ "$kind" = "text" ]; then
    out=$(node tools/render.mjs "${d%/}" 2>&1) || { echo "FAIL render ${d%/}"; echo "$out"; fails=$((fails+1)); continue; }
    echo "ok  ${d%/} — $out"
    [ "$kind" = "carousel" ] && carousels=$((carousels+1)) || cards=$((cards+1))
  fi
  if [ "$kind" = "text" ] || [ -n "$(jq -r '.body // empty' "${d}copy.json")" ]; then
    out=$(node tools/lint_text.mjs "${d%/}" 2>&1) || { echo "FAIL lint ${d%/}"; echo "$out"; fails=$((fails+1)); continue; }
    echo "ok  ${d%/} — $out"; texts=$((texts+1))
  fi
done
# every refusal fixture breaks one rule; it must exit 2 AND name that rule, or the rule is
# not what refused it
for d in tools/test/refuse/*/; do
  nref=$((nref+1)); want=$(head -1 "${d}expect.txt")
  out=$(node tools/lint_text.mjs "${d%/}" 2>&1); rc=$?
  if [ $rc -eq 2 ] && grep -qF -- "$want" <<<"$out"; then refused=$((refused+1)); echo "ok  refused ${d%/} — $want"
  else echo "FAIL ${d%/} must be refused with \"$want\" (exit $rc)"; echo "$out"; fails=$((fails+1)); fi
done
tout=$(node --test --test-reporter=tap tools/test/*.test.mjs 2>&1); trc=$?
tpass=$(sed -n 's/^# pass //p' <<<"$tout"); tfail=$(sed -n 's/^# fail //p' <<<"$tout")
[ $trc -eq 0 ] || { echo "$tout"; fails=$((fails+1)); }
sout=$(printf 'verify: dry run\n' | SLACK_DRY_RUN=1 SLACK_WEBHOOK_URL=https://hooks.slack.invalid/x bash tools/slack.sh 2>&1) \
  && grep -q '"text": *"verify: dry run' <<<"$sout" && echo "ok  slack.sh dry run" || { echo "FAIL slack.sh dry run"; echo "$sout"; fails=$((fails+1)); }
for s in tools/*.sh; do bash -n "$s" || { echo "FAIL syntax $s"; fails=$((fails+1)); }; done
echo "----"
echo "$carousels carousel(s) and $cards card(s) rendered and gated, $texts text body(ies) linted, $refused/$nref refusal(s) as expected, unit tests ${tpass:-0} pass ${tfail:-?} fail, $skipped published post(s) skipped, $fails failure(s)"
[ $fails -eq 0 ]
