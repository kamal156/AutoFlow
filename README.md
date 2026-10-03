# AutoFlow

Automates the Suno -> YouTube/Facebook content pipeline on a self-hosted **Windmill**
instance. Two human touchpoints remain: generating the Suno tracks, and approving the
final render.

One repo (`github.com/kamal156/AutoFlow`), two hosts, one stack. Both run the same
`docker-compose.yml` (Windmill **Community Edition** + Postgres):

| Host | Checkout | Docker runs in | Start it with |
|---|---|---|---|
| **Windows PC** | `D:\AutoFlow` | **WSL 2 Ubuntu** (Docker Engine inside the distro, no Docker Desktop) | any `wsl` command - see below |
| **Mac** | `/Users/kamal/Desktop/AutoFlow` | Colima | `colima start && docker compose up -d` |

Both hosts expose the UI at http://localhost:8000 (default login
`admin@windmill.dev` / `changeme` - change it after the first sign-in) and are
provisioned from the same code with `provision.py`.

Full plan: `C:\Users\kamal\.claude\plans\splendid-imagining-crayon.md`.

## Pipeline stages

| Stage | Who | Status |
|---|---|---|
| 1. Research -> longtail -> thumbnail -> metadata | Auto (`scripts\new-job.ps1`) | **Phase 1 - built** (CLI needs reinstalling on Windows, see below) |
| 2. Generate 6-8 Suno tracks | **You** | manual by design |
| 3. Stitch audio + image -> MP4 | Auto (EverLoop CLI) | **Phase 2 - built** |
| 4. Approve the render | **You** | Phase 3 |
| 5. Upload to YouTube + Facebook | Auto (Windmill) | Phase 3-5 |

## What's in here

| File | Purpose |
|---|---|
| `docker-compose.yml` | **The Windmill stack (both hosts):** Postgres 16 + Windmill server + 1 worker + 1 native worker. Compose project name pinned to `windmill` |
| `.env` | Pinned `WM_VERSION`, generated Postgres password, port, `BASE_URL`. **Not in git** - one per host |
| `provision.py` | Creates the workspace, variable, flow and schedule over the API. Stdlib only, idempotent. Auth: `WM_TOKEN` or `WM_PASSWORD` |
| `docs/ui/*.md` | The Info + Manual text shown in the Windmill UI for the flow, variable and schedule. `provision.py` pushes it on every run, so edit it here, not in the UI |
| `flow/fetch_new_items.py` | Flow step `a` - reads an RSS feed, returns only unseen items |
| `flow/post_to_discord.py` | Flow step `c` - posts one item to Discord, inside the loop |
| `scripts/open-windmill.bat` | Windows: target of the **Windmill** desktop icon. Starts the WSL stack if it is down, waits for the API, opens http://localhost:8000 |
| `scripts/keep-wsl-alive.vbs` | Windows: hidden keep-alive session so WSL does not stop Ubuntu (and Windmill) when idle. Started by `open-windmill.bat` |
| `scripts/windmill-at-login.vbs` | Windows: target of the **Windmill (start at login)** Startup entry. Starts the keep-alive and the stack silently - no window, no browser |
| `scripts/create-windmill-shortcut.vbs` | Windows: (re)create the desktop icon **and** the Startup entry - `cscript //nologo scripts\create-windmill-shortcut.vbs` (VBScript, because Quick Heal quarantines files PowerShell creates) |
| `scripts/provision.bat` | Windows: double-click to re-run `provision.py` with the portable CPython |
| `scripts/new-job.ps1`, `scripts/validate-job.js`, `prompts/`, `config/` | Phase 1 research job (see below) |
| `AutoFlow.bat`, `scripts/setup-windmill.ps1`, `scripts/stop-autoflow.bat`, `scripts/create-desktop-shortcut.ps1`, `scripts/make-icon.js`, `assets/` | **Legacy** native-Windows launcher (see the end of this file). Not used by the WSL setup |

`provision.py` is idempotent - edit the `.py` files in `flow/` (or the text in
`docs/ui/`), re-run it, and the deployed flow updates in place. It never overwrites
the webhook value, and on an existing schedule it refreshes only the summary and
description, leaving the cron, args and on/off state as set in the UI. The flow is built
through the API rather than clicked together in the browser, so it survives a rebuild on
either host.

## Running on the Windows PC (WSL + Docker)

Windmill runs in Docker inside the **Ubuntu** WSL 2 distro, from the compose file in
this folder (`/mnt/d/AutoFlow` as seen from Linux). Docker Engine was installed in the
distro with `get.docker.com`. Docker Desktop is not used; its `docker-desktop` distro
is present but stopped.

**Auto-start.** `/etc/wsl.conf` enables systemd, the `docker` service is enabled, and
every container has `restart: unless-stopped`, so booting the distro brings Windmill
back on its own.

**WSL stops Ubuntu ~20 s after the last `wsl` session exits** (verified 2026-10-03,
WSL 3.0.1) and Windmill goes down with it, even though the containers are healthy.
A one-off `wsl ...` command therefore starts Windmill only for a moment. The desktop
icon handles this: `scripts/keep-wsl-alive.vbs` starts one hidden
`flock ... sleep infinity` session that holds the distro up until Windows logs off or
`wsl --shutdown`. The `flock` makes repeat clicks harmless. If Windmill drops after a
restart, just double-click the icon again.

**At login** the Startup-folder entry `Windmill (start at login)` runs
`scripts/windmill-at-login.vbs`, so Windmill is already up (~6 s after login) by the
time you click the icon. To turn that off, delete the shortcut from `shell:startup`
(Win+R -> `shell:startup`).

| Action | Command (from PowerShell / cmd) |
|---|---|
| **Open Windmill** | double-click the **Windmill** desktop icon - it starts the stack first if needed (~15 s from stopped) |
| Status / wake WSL | `wsl -d Ubuntu -u root -e docker ps` |
| Start the stack | `wsl -d Ubuntu -u root -e sh -c "cd /mnt/d/AutoFlow && docker compose up -d"` |
| Stop (keeps data) | `wsl -d Ubuntu -u root -e sh -c "cd /mnt/d/AutoFlow && docker compose stop"` |
| Worker logs | `wsl -d Ubuntu -u root -e sh -c "cd /mnt/d/AutoFlow && docker compose logs -f windmill_worker"` |
| Server logs | same, with `windmill_server` |
| Re-provision | `scripts\provision.bat`, or `C:\Users\kamal\tools\python\python.exe provision.py` |
| Upgrade Windmill | bump `WM_VERSION` in `.env`, then `... docker compose pull && docker compose up -d`; afterwards run `u/admin/hub_sync` in the `admins` workspace |
| Shut WSL down entirely | `wsl --shutdown` |

`-u root` is used so the commands work without the `docker` group membership taking
effect in a fresh login.

**Networking.** Compose publishes `127.0.0.1:8000` inside the VM and WSL's
`wslrelay.exe` forwards it to `localhost:8000` on Windows. Nothing is exposed to the
LAN.

**Data.** Postgres lives in the Docker volume `windmill_db_data` inside the WSL virtual
disk, **not** in `D:\PostgresLocal`. That native Postgres still serves `nepse_market`
and is unrelated. The worker's pip/uv cache is the `windmill_worker_dependency_cache` volume, so
only the first run of a new dependency is slow. Images take ~6 GB inside WSL.
To wipe the instance completely: `... docker compose down -v`.

**Authentication for scripts.** Prefer an API token over the password: in the UI open
the user menu -> **Account settings -> Tokens**, then
`set WM_TOKEN=<token>` before `scripts\provision.bat` (or `WM_TOKEN=... python provision.py`).
Revoke tokens you no longer need from the same page.

### What the instance holds (2026-10-03)

| Workspace | Item | Kind |
|---|---|---|
| `main` | `u/admin/rss_to_discord` | flow |
| `main` | `u/admin/discord_webhook` | secret variable |
| `main` | `u/admin/rss_to_discord` | schedule (hourly, **off**) |
| `admins` | `u/admin/hub_sync` | Windmill's own script: pulls resource types from the Hub |
| `admins` | `f/app_themes/theme_0` | Windmill's default app theme |

Each item carries an **Info** and a **Manual** section in its description in the UI.
No resources, apps or other scripts exist yet; the ~1,000 resource types are the Hub
catalogue.

## Running on the Mac (Docker via Colima)

Colima does **not** start at login, so after a reboot:

```bash
colima start && cd /Users/kamal/Desktop/AutoFlow && docker compose up -d
```

| Task | Command |
|---|---|
| Stop the stack (keeps data) | `docker compose down` |
| Stop the VM too (frees ~4 GB RAM) | `colima stop` |
| Logs from a worker | `docker compose logs -f windmill_worker` |
| Recreate the flow from code | `python3 provision.py` |
| Auto-start Colima at login | `brew services start colima` |

The Mac had ~440 MB free after install (the stack costs about 4.8 GB in Docker images
plus the Colima VM disk); macOS gets unstable below ~1 GB free. To reclaim everything:
`docker compose down -v && colima delete -f`.

`WM_VERSION` is pinned per host in `.env` (Mac: 1.365.0 at install; Windows: 1.821.0).
Upgrade deliberately with `docker compose pull && docker compose up -d`. The
`windmill-lsp` editor autocomplete service is left out on purpose (it needs the Caddy
`/ws` proxy from the official stack).

## The `rss_to_discord` flow

The first flow, brought over from the Mac. It is a template for the pipeline flows:

```
Input (feed_url, max_items)
  └─ a: fetch new items      Python - feedparser, dedupes via wmill state
      └─ b: for each item    loop over results.a
          └─ c: post to discord    retries 3x exponential
```

The full manual (setup, day-to-day use, troubleshooting) is in
`docs/ui/rss_to_discord.flow.md` and on the flow's page in Windmill. In short, after
provisioning, on either host:

1. **Change the admin password.** Bottom-left `User (admin)` -> set a real password.
2. **Paste your Discord webhook.** `Variables` -> `u/admin/discord_webhook` -> replace
   `REPLACE_ME_with_your_discord_webhook_url`. It is stored encrypted.
3. **Seed it.** Run the flow once by hand; the first run records the feed and posts
   nothing.
4. **Enable the schedule.** `Schedules` -> `u/admin/rss_to_discord` -> toggle on.
   Hourly (`0 0 * * * *`, seconds first, Asia/Kathmandu), deliberately shipped **off**.

Things that will bite you:

- **The first run of any new dependency is slow** (~30 s while `feedparser` installs).
  It is cached after that. Don't mistake it for a hang.
- **State is per flow-step path.** Rename step `a` or move the flow and the dedupe
  history is gone; the next run re-seeds and posts nothing.
- **Edits made in the UI are overwritten** by the next `provision.py` run. Change the
  files in `flow/` and `docs/ui/` instead.

## Phase 1: the research job (Windows)

Phase 1 runs on the Windows host itself (not inside Windmill) and needs the Claude
Code **CLI** (the desktop app is a separate thing and does not provide `claude -p`),
plus the Nexlev MCP server registered locally. The Nexlev connector attached to your
claude.ai account is *not* visible to the CLI.

**Status 2026-10-03: the CLI is not installed.** It lived in
`D:\Claude Projects\AutoFlow\npm-global`, which was removed with the old checkout. The
User PATH still points there. Reinstall into this checkout (`npm-global/` is
gitignored, and `new-job.ps1` falls back to `npm-global\claude.cmd` here):

```powershell
# 1. CLI with npm's global prefix on D: (C: is nearly full). --allow-scripts lets the
#    postinstall run; the install works regardless, since claude.exe ships in the package.
npm config set prefix "D:\AutoFlow\npm-global"
npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code

# 2. Put D:\AutoFlow\npm-global on the User PATH (replacing the stale
#    D:\Claude Projects\AutoFlow\npm-global entry). Open a NEW terminal afterwards.

# 3. Nexlev at *user* scope, so it resolves from any directory. (Plain
#    `claude mcp add` writes config tied to the current folder, which breaks as
#    soon as a script runs from somewhere else.) User-scope config lives in
#    ~/.claude.json, so this may still be registered from before - check first.
claude mcp add --scope user --transport http nexlev https://prod.dashboard.nexlev.io/api/claude-mcp

# 4. Two interactive logins. Neither can be scripted; both open a browser.
#    Run `claude` in a NEW terminal, then:
#      a) /login  - signs the CLI in to your Claude account. This is SEPARATE
#                   from the desktop app's session.
#      b) /mcp    - authenticate nexlev via OAuth.
#    Headless runs reuse both stored tokens afterwards.
```

### Do not trust `claude mcp list`

It shows your claude.ai account connectors as `claude.ai NexLev ... Connected`, but
**headless `claude -p` does not load them** - they belong to interactive and desktop
sessions. That is why a separately registered `nexlev` server exists above, and why it
needs its own `/mcp` OAuth even though the claude.ai connector is already authorised.

Verify functionally instead. This must print `FOUND`, not `NO_TOOL`:

```powershell
"Call the youtube_search tool with query 'lofi'. If no such tool exists, reply exactly NO_TOOL." | claude -p --output-format json --allowedTools "mcp__nexlev"
```

The `/login` step is confirmed by `"is_error": false` from:

```powershell
"Reply with exactly: PLUMBING OK" | claude -p --output-format json
```

### Usage

```powershell
.\scripts\new-job.ps1 -SeedKeyword "lofi study beats"
```

Creates `jobs\<timestamp>-<slug>\` containing:

```
job.json      all publish metadata (YT long/short, FB feed/reel)
thumb.jpg     generated thumbnail
state.json    {"stage": "awaiting_audio"}
audio\        <- drop your 6-8 Suno tracks here
render\        output from the EverLoop CLI (Phase 2)
_prompt.md    the resolved prompt that was sent
_session.json raw Claude session log, for debugging a bad run
```

Add `-DryRun` to render the prompt without calling Claude.

### Design notes

**One fat agentic call, never many thin ones.** A single `claude -p` invocation does
research, longtail selection, thumbnail inspiration, thumbnail generation and metadata
writing. Each invocation reloads context from scratch and draws on subscription usage
limits, so six small calls cost far more than one large one.

**Validation is deliberately strict.** `validate-job.js` enforces the platform limits
that would otherwise fail at publish time - after a render has already burned an hour.
It also requires `research.outlier_references` to be non-empty, which is the cheapest
available proof that the agent actually queried Nexlev rather than inventing a keyword
from its own priors.

**Billing caveat.** `claude -p` currently draws from your Claude subscription's usage
limits rather than API credits. Anthropic announced a change on 2026-06-15 that would
have moved programmatic usage onto separately-billed Agent SDK credits, then paused it.
If that reverses, the fallback is setting `ANTHROPIC_API_KEY` - no code change needed.

## Legacy: native Windows Windmill (superseded)

Before WSL was available, the PC ran Windmill natively: `AutoFlow.bat` started the
local PostgreSQL in `D:\PostgresLocal` and `windmill\windmill-ee.exe`
(`MODE=standalone`), which `scripts\setup-windmill.ps1` downloaded together with
portable PowerShell 7 and `uv`. It was abandoned because of two blockers (verified
2026-09-02, v1.801.0):

1. The Windows exe does **not embed the web UI** - every page returns 404; only
   `/api/*` works.
2. The **worker refuses to run any job** without an Enterprise licence key
   (`workers require a valid license key`). There is no Community build for Windows.

The files are kept for reference only. **Do not run `AutoFlow.bat` or
`scripts\stop-autoflow.bat` on the WSL setup**: both still assume
`D:\PostgresLocal` and `windmill-ee.exe`, and the launcher would start downloading
the ~600 MB native toolchain.
