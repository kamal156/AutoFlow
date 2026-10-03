## Info

**What it does:** reads an RSS/Atom feed and posts each entry it has not seen before
to a Discord channel, one message per item (`**title**` + link).

**Part of:** AutoFlow (`D:\AutoFlow`). It is also the template the Suno -> YouTube /
Facebook pipeline flows are built from.

| | |
|---|---|
| Inputs | `feed_url` (default `https://hnrss.org/frontpage`), `max_items` (default `5`) |
| Step a - fetch new items | Python + feedparser. Dedupes against Windmill state (the last 200 links seen) |
| Step b - post each item | For-loop over `results.a`, one at a time, stops on the first failure |
| Step c - post to discord | Python + requests. Retries 3x with backoff (2 s, 4 s, 8 s) |
| Uses | secret variable `u/admin/discord_webhook` |
| Triggered by | schedule `u/admin/rss_to_discord` (hourly, Asia/Kathmandu, **off** by default) |
| Source of truth | `D:\AutoFlow\flow\*.py` + `provision.py` + this text in `docs\ui\` |

**Do not edit this flow in the UI.** The next `provision.py` run overwrites the
flow, including this description. Change the files on disk instead.

## Manual

### First-time setup

1. **Webhook:** in Discord, open the channel settings, go to **Integrations ->
   Webhooks -> New Webhook -> Copy Webhook URL**. In Windmill, go to
   **Variables -> `u/admin/discord_webhook` -> Edit**, paste the URL into Value, and save.
2. **Seed run:** press **Run** here with the defaults. The first run posts
   **nothing** on purpose: it only records what is already in the feed.
3. **Check run:** press Run again later. Only items published since then are posted.
4. **Go live:** **Schedules -> `u/admin/rss_to_discord`** -> toggle on.

### Day to day

- **Pause:** toggle the schedule off. The dedupe history is kept.
- **Change the feed or cap for scheduled runs:** edit the **args on the schedule**.
  The defaults here only apply to manual runs.
- **Switching to a different feed:** its first run can post up to `max_items` older
  entries, because none of its links are in the history yet.
- **Several feeds:** copy the flow to a new path, one per feed. Each path keeps its
  own history. Pointing several schedules at this one flow makes them share and
  overwrite a single history.

### Changing the code

1. Edit `D:\AutoFlow\flow\fetch_new_items.py` or `post_to_discord.py` (or this
   description in `docs\ui\`).
2. Redeploy: `C:\Users\kamal\tools\python\python.exe D:\AutoFlow\provision.py`.
   If the admin password has been changed, set `WM_PASSWORD` first. It is
   idempotent, and it leaves the webhook value and the schedule's settings alone.
3. **Never rename step `a` or move the flow.** The dedupe history is tied to that
   path. A rename starts over, and the next run re-seeds and posts nothing.

### Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `variable u/admin/discord_webhook is unset` | Setup step 1 has not been done |
| Step c fails with 401 / 404 | The webhook was deleted or regenerated in Discord. Paste the new URL |
| Step c fails with 429 | Discord rate limit. Retries usually absorb it; otherwise lower `max_items` |
| `could not parse feed` | `feed_url` is wrong or is not RSS/Atom. Open it in a browser |
| Run took ~30 s or more | First run after a deploy installs feedparser/requests. It is cached after that |
| Run succeeded but posted nothing | Normal on the first run, or when there is nothing new. Check step a's result (`[]`) |
| Failures go unnoticed | No error handler is set. **Workspace settings -> Error handler** can send alerts to Slack/Teams/email/a script |

### The instance

Windmill CE runs in Docker inside **WSL Ubuntu**, from `D:\AutoFlow\docker-compose.yml`
(project `windmill`), at http://localhost:8000.

- Status: `wsl -d Ubuntu -u root -e docker ps`
- Start: `wsl -d Ubuntu -u root -e sh -c "cd /mnt/d/AutoFlow && docker compose up -d"`
- Stop (keeps data): `wsl -d Ubuntu -u root -e sh -c "cd /mnt/d/AutoFlow && docker compose stop"`
- Worker logs: `wsl -d Ubuntu -u root -e sh -c "cd /mnt/d/AutoFlow && docker compose logs -f windmill_worker"`
