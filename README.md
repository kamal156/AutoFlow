# Windmill — self-hosted automation, running locally

Canvas flow builder + Python steps, on Docker. Set up 2026-08-27.

**UI:** http://localhost:8000 · **Login:** `admin@windmill.dev` / `changeme`
**Workspace:** `main` · **Flow:** `u/admin/rss_to_discord`

---

## ⚠️ Do these three things first

1. **Change the admin password.** UI → bottom-left `User (admin)` → set a real password.
   Until you do, anything that can reach port 8000 can run code on your Mac.
2. **Paste your Discord webhook.** UI → `Variables` → `u/admin/discord_webhook` → replace
   `REPLACE_ME_with_your_discord_webhook_url` with the real URL. It's stored encrypted.
   (Discord: Server Settings → Integrations → Webhooks → New Webhook → Copy URL.)
3. **Enable the schedule.** UI → `Schedules` → `u/admin/rss_to_discord` → toggle on.
   It's hourly (`0 0 * * * *`, Asia/Kathmandu) and deliberately shipped **off**.

## ⚠️ Disk space

This machine had 6.7 GB free before install and has **~440 MB free now**. The stack costs
about 4.8 GB (Docker images + the Colima VM disk). macOS gets unstable below ~1 GB free.

Free space before you do much else. To reclaim everything this added:

```bash
docker compose down -v && colima delete -f
```

---

## Daily operation

Colima does **not** start at login, so after a reboot:

```bash
colima start && cd /Users/kamal/Desktop/windmill && docker compose up -d
```

| Task | Command |
|---|---|
| Stop the stack (keeps data) | `docker compose down` |
| Stop the VM too (frees ~4 GB RAM) | `colima stop` |
| Logs from a worker | `docker compose logs -f windmill_worker` |
| Recreate the flow from code | `python3 provision.py` |
| Auto-start Colima at login | `brew services start colima` |

## What's in here

| File | Purpose |
|---|---|
| `docker-compose.yml` | Postgres + Windmill server + 1 worker + 1 native worker |
| `.env` | Pinned version, generated Postgres password, port. **Not in git.** |
| `flow/fetch_new_items.py` | Step `a` — reads the feed, returns only unseen items |
| `flow/post_to_discord.py` | Step `c` — posts one item, inside the loop |
| `provision.py` | Creates the workspace, variable, flow and schedule over the API |

`provision.py` is idempotent — edit the `.py` files in `flow/`, re-run it, and the deployed
flow updates. That's the reason the flow was built through the API rather than clicked
together in the browser: it survives a rebuild.

## How the flow works

```
Input (feed_url, max_items)
  └─ a: fetch new items      Python — feedparser, dedupes via wmill state
      └─ b: for each item    loop over results.a
          └─ c: post to discord    retries 3× exponential
```

**Verified working:** a full run completed successfully (returned `[]` — the seeding run),
and a forced run confirmed the loop passes items into step `c` and retries on failure.

## Things that will bite you

- **The first run of any new dependency is slow** (~30 s while `feedparser` installs).
  It's cached in a named volume after that. Don't mistake it for a hang.
- **State is per flow-step path.** Rename step `a` or move the flow and the dedupe history
  is gone, so the next run re-seeds and posts nothing. That's recoverable, just confusing.
- **The first run after enabling the schedule posts nothing** — by design, so deploying
  doesn't dump the whole HN front page into your channel.
- **Outbound requests come from the worker container, not your Mac.** If a fetch fails,
  `docker compose logs windmill_worker` is where the answer is.
- **No TLS, bound to 127.0.0.1.** Fine locally. If this ever moves to a VPS, add the Caddy
  service from the official stack and set `BASE_URL` to a real https:// domain first.
- **`WM_VERSION` is pinned** to 1.365.0. The UI will nag about a newer release; upgrade
  deliberately with `docker compose pull && docker compose up -d`.
- **No editor autocomplete.** The `windmill-lsp` service needs Caddy's `/ws` proxy, so it
  was left out. The code editor works, minus type hints.

## Reusing this for something else

The flow is a template. To point it at a different job, either edit `flow/*.py` and re-run
`provision.py`, or ignore the flow entirely — for a single existing script, `+ Script` in the
UI with a `main()` entry point and a schedule attached is less machinery than the canvas.
