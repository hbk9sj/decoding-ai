# decoding-ai

The content pipeline behind the LinkedIn profile **Decoding AI by Nueravi**: a scheduled
Claude routine writes one post, a gate refuses anything that breaks the contract, and
GitHub Actions queues it in Buffer.

- `BRIEF.md` — what the routine reads before it writes. The rules, and the measured
  evidence for each one.
- `render/` — four editorial slide looks (broadsheet, riso, field notes, memo), the fonts
  they are set in, and `page.html`, which draws one page of one carousel.
- `render/fixtures/` — one worked carousel per look, used to prove the templates still
  render (they are the gallery and the regression test).
- `tools/render.mjs` — renders a carousel to PNG pages and a 1080×1350 PDF, and gates it:
  word budgets, safe area, overlap, contrast, minimum type size, font fallback, page size,
  file size.
- `tools/lint_text.mjs` — the text-post contract (hook, length, links, hashtags, banned
  phrases, reading level, action line, source).
- `tools/post.sh` — publishes the PDF to the `assets` branch, waits for the raw URL, then
  creates the Buffer post. Refuses if the channel is disconnected or the plan's
  scheduled-post cap is nearly full.
- `.github/workflows/publish.yml` — picks up any `posts/<folder>` that has a `copy.json`
  and no `run.md`, runs the job, commits the record back.

## Verify

```bash
cd tools && npm ci && npx playwright install chromium
bash tools/verify.sh        # must end "0 failure(s)"
```

## Secrets (Actions, and the routine's environment)

`BUFFER_ACCESS_TOKEN`, `BUFFER_CHANNEL_ID`, `BUFFER_ORGANIZATION_ID`. Nothing else, and
none of them in the repo.
