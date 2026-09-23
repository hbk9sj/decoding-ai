# decoding-ai

The content pipeline behind the LinkedIn profile **Decoding AI by Nueravi**: a scheduled
Claude routine writes one post, a gate refuses anything that breaks the contract, and
GitHub Actions queues it in Buffer.

- `BRIEF.md` — what the routine reads before it writes. The rules, and the measured
  evidence for each one.
- `render/` — four editorial slide looks (broadsheet, riso, field notes, memo), the fonts
  they are set in, and `page.html`, which draws one page of one carousel, or a text
  post's card.
- `render/fixtures/` — one worked carousel and one card per look, used to prove the
  templates still render (they are the gallery and the regression test).
- `tools/render.mjs` — renders a carousel to PNG pages and a 1080×1350 PDF, or a text
  post's card to `card.png`, and gates it: word budgets, safe area, overlap, contrast,
  minimum type size, font fallback, page size, file size.
- `tools/lint_text.mjs` — the post contract (hook, length, the source line as the only
  URL, hashtags, banned phrases, reading level, action line, the card, evidence for
  "tried", the second comment). `tools/test/refuse/` holds one post per rule that it must
  refuse.
- `tools/post.sh` — publishes the PDF or card to the `assets` branch, waits for the raw
  URL, spaces the post 12 h from any other (two a day at most), creates the Buffer post, then reads it back.
  Refuses if the channel is disconnected, link shortening is on, or the scheduled-post
  cap is full; deletes the post if Buffer changed the text or attached a link card.
- `tools/spacing.mjs` — the 12-hour rule (unit tests in `tools/test/`).
- `tools/slack.sh`, `tools/live_check.sh`, `tools/metrics.sh` — the Queued, Live and
  Failed alerts, and the daily numbers in `state/metrics.json` (Monday scoreboard).
  Carousel numbers and follower count go in `state/manual.csv` by hand.
- `.github/workflows/publish.yml` — every 30 min: picks up any `posts/<folder>` that has a
  `copy.json` and no `run.md`, runs the job, checks whether queued posts went live, and
  commits the record back. `metrics.yml` runs daily at 07:00 IST.
- `roster.md` — the creators to comment on before each post (used once approved).
  `PROFILE.md` — the one-time profile checklist.

## Verify

```bash
(cd tools && npm ci && npx playwright install chromium)
bash tools/verify.sh        # must end "0 failure(s)"
```

## The Buffer queue cap

The plan's 10-scheduled-post limit is **per channel**, not per account — checked on
22 Sep 2026 by queueing an 11th post while the account already held 10 across its
channels, which Buffer accepted. So Decoding AI has its own 10 slots and the other
channels on the account cannot crowd it out. `tools/post.sh` counts only this channel's
pending posts and refuses loudly, in `run.md`, if they ever reach the cap. Four posts a
week uses four of the ten, so the cap is not a constraint in practice.

## Secrets (Actions, and the routine's environment)

`BUFFER_ACCESS_TOKEN`, `BUFFER_CHANNEL_ID`, `BUFFER_ORGANIZATION_ID`, and
`SLACK_WEBHOOK_URL` (Actions only; without it the alerts are skipped with a warning and
posting carries on). None of them in the repo.

A live end-to-end check that never reaches LinkedIn: a folder whose `job.json` is
`{"smoke": true}` is queued as a draft, read back, and deleted.
