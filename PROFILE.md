# Profile checklist — one time, by hand

Things only Suraj can do. The pipeline cannot touch profile settings, and should not.
Tick them in order; the first one decides where the rest happen.

## 1. Decide which profile this runs on (blocking)

LinkedIn's name rules for personal profiles do not allow "pseudonyms, fake names, business
names", and its community policies say "We don't allow fake profiles or entities".
"Decoding AI by Nueravi" is a business name on a personal profile, so the account can be
restricted at any time, and everything built on it (followers, the newsletter) goes with it.

Pick one:

- **(a) Rename this profile to your real name.** "Decoding AI" moves to the headline and
  the newsletter name. Keeps the followers it already has. Nothing in the repo changes.
- **(b) Run it as a series on your own profile.** Connect that profile in Buffer and
  replace the `BUFFER_CHANNEL_ID` secret. Starts from your existing network.
- **(c) A Nueravi Company Page.** Allowed to carry a business name, but pages reach far
  fewer people than profiles do.

The pipeline works with any of the three; only the channel secret changes.

## 2. Settings on the chosen profile

- [ ] Follow as the primary button, if LinkedIn still offers it (Settings → Visibility →
      Followers). Not checked in 2026; if the option is gone, skip it.
- [ ] Headline: who it is for and what they get, e.g. "Decoding AI for people who use it
      at work · plain English, a named source, one thing to do".
- [ ] About: the promise from `BRIEF.md` in three short lines, then the four slots
      (Mon news, Tue decoded, Wed tried, Thu belief).
- [ ] Featured: pin the best-performing carousel (see `state/metrics.json` and
      `state/manual.csv`), and replace it when a better one lands.

## 3. The newsletter (after step 1 only)

A LinkedIn newsletter belongs to the profile that creates it and cannot be moved, which is
why it waits for step 1. Once decided: create it (weekly, Sunday), named "Decoding AI", and
say so — the step where the Thursday routine drafts each edition into Slack is built then,
not before.

## 4. Slack alerts

1. api.slack.com/apps → Create New App → From scratch → name it "Decoding AI alerts",
   pick your workspace.
2. Incoming Webhooks → switch on → Add New Webhook → pick the channel → copy the URL.
3. `gh secret set SLACK_WEBHOOK_URL -R hbk9sj/decoding-ai` and paste it when asked.

Until then every alert is skipped with a warning in the Actions log, and posting carries on.

## 5. Once a week (Monday, from the scoreboard)

Open each carousel on LinkedIn, and add a row to `state/manual.csv` with its impressions,
reactions, comments and reposts, plus your follower count. Buffer has no analytics for
document posts, so without this row the routines cannot see how carousels are doing.

## 6. The roster

Read `roster.md`, cut anyone you would not comment on, add anyone missing, and change its
status line to `status: approved`. Until then the alerts say "roster not approved yet".
