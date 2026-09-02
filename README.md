# AutoFlow

Automates the Suno -> YouTube/Facebook content pipeline on a self-hosted **Windmill**
instance. Two human touchpoints remain: generating the Suno tracks, and approving the
final render.

One repo (`github.com/kamal156/AutoFlow`), two hosts:

| Host | Windmill runs as | Start it with |
|---|---|---|
| **Windows PC** (`D:\Claude Projects\AutoFlow`) | native `windmill-ee.exe`, standalone, on the local PostgreSQL | the **AutoFlow** desktop icon / `AutoFlow.bat` |
| **Mac** (`/Users/kamal/Desktop/AutoFlow`) | Docker (`docker-compose.yml`) via Colima | `colima start && docker compose up -d` |

Both hosts expose the same UI at http://localhost:8000 (default login
`admin@windmill.dev` / `changeme` - change it after the first sign-in) and are
provisioned from the same code with `provision.py`.

Full plan: `C:\Users\kamal\.claude\plans\splendid-imagining-crayon.md`.

## Pipeline stages

| Stage | Who | Status |
|---|---|---|
| 1. Research -> longtail -> thumbnail -> metadata | Auto (`scripts\new-job.ps1`) | **Phase 1 - built** |
| 2. Generate 6-8 Suno tracks | **You** | manual by design |
| 3. Stitch audio + image -> MP4 | Auto (EverLoop CLI) | **Phase 2 - built** |
| 4. Approve the render | **You** | Phase 3 |
| 5. Upload to YouTube + Facebook | Auto (Windmill) | Phase 3-5 |

## What's in here

| File | Purpose |
|---|---|
| `AutoFlow.bat` | **Windows launcher.** Starts PostgreSQL + Windmill, runs `provision.py`, opens the UI |
| `scripts/setup-windmill.ps1` | Windows first-run: downloads `windmill-ee.exe`, portable PowerShell 7 and `uv`; creates the `windmill` database |
| `scripts/provision.bat` | Windows: re-run `provision.py` by hand (e.g. after changing the admin password) |
| `scripts/stop-autoflow.bat` | Windows: stop Windmill (PostgreSQL stays up for the NEPSE database) |
| `scripts/create-desktop-shortcut.ps1` | Windows: (re)create the desktop icon |
| `scripts/make-icon.js` | Windows: redraw `assets/autoflow.ico` |
| `scripts/new-job.ps1`, `scripts/validate-job.js`, `prompts/`, `schemas/`, `config/` | Phase 1 research job (see below) |
| `docker-compose.yml` | **Mac stack:** Postgres + Windmill server + 1 worker + 1 native worker |
| `.env` | Mac only: pinned `WM_VERSION`, generated Postgres password, port. **Not in git.** |
| `provision.py` | Creates the workspace, variable, flow and schedule over the API. Stdlib only, idempotent |
| `flow/fetch_new_items.py` | Flow step `a` - reads an RSS feed, returns only unseen items |
| `flow/post_to_discord.py` | Flow step `c` - posts one item to Discord, inside the loop |

`provision.py` is idempotent - edit the `.py` files in `flow/`, re-run it, and the
deployed flow updates in place. The flow is built through the API rather than clicked
together in the browser so it survives a rebuild on either host.

## Running on the Windows PC

| Action | How |
|---|---|
| Start | double-click the **AutoFlow** desktop icon (or `AutoFlow.bat`) |
| Open the UI | it opens automatically at http://localhost:8000 |
| First login | `admin@windmill.dev` / `changeme` - change it after signing in |
| Re-provision the flows | `scripts\provision.bat` (set `WM_PASSWORD` first if you changed the password) |
| Stop Windmill | `scripts\stop-autoflow.bat` |
| Logs | `windmill\logs\windmill.log` |
| Recreate the icon | `powershell -File scripts\create-desktop-shortcut.ps1` |
| Redraw the icon | `node scripts\make-icon.js` |

Nothing is exposed to the network: Windmill binds to 127.0.0.1:8000 and uses the local
PostgreSQL in `D:\PostgresLocal` (database `windmill`, alongside `nepse_market`).

**First double-click** runs `scripts\setup-windmill.ps1`, which downloads into this
folder (no admin rights needed, everything stays on D:):

- `windmill\windmill-ee.exe` (~466 MB) - the native Windows Windmill binary from
  https://github.com/windmill-labs/windmill/releases. It is the Enterprise build
  because that is the only Windows build published. Server and worker run in one
  process (`MODE=standalone`).

  **Licence caveat (verified 2026-09-02, v1.801.0):** the server, UI and API work
  without a key (the launcher provisions the flow fine), but the **worker refuses to
  run any job** until a valid Enterprise licence key is set in Superadmin settings
  (`workers require a valid license key`). Windmill's docs list "Windows Native
  Workers" as a Self-Hosted Enterprise feature; there is no Community build for
  Windows. Options: a one-month trial key from https://www.windmill.dev/pricing, or
  run the free Community edition somewhere Linux-based (the Mac stack, WSL, a VM or
  a VPS). This PC has neither Docker nor WSL and no admin rights to add them.
- `tools\pwsh\` (~106 MB) - portable PowerShell 7. The Windmill Windows worker only
  runs PowerShell steps through `pwsh.exe`, not Windows PowerShell 5.1.
- `tools\uv\` (~20 MB) - `uv`, which Windmill uses to install Python step
  dependencies (`feedparser`, `requests`, `wmill`) into its cache. The interpreter
  itself is the portable CPython in `C:\Users\kamal\tools\python` (`PYTHON_PATH`).

The first start then applies Windmill's database migrations, which can take a few
minutes; the launcher waits up to five minutes, then runs `provision.py` and opens the
browser. The launcher window stays visible so a download or migration in progress
does not look like a hang.

The launcher puts these on the worker's PATH so jobs can call them directly:
`claude` (`npm-global`), `node`, `ffmpeg`, `python`, `uv`, `psql`, `pwsh`. Job scratch
space is redirected to `windmill\tmp` to keep it off the full C: drive.

Optional, not fetched: `windmill_duckdb_ffi_internal.dll` (~30 MB) from the same
release page, only needed for DuckDB scripts. Drop it next to the exe if you use them.

## Running on the Mac (Docker)

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

`WM_VERSION` in `.env` is pinned (1.365.0 at install). Upgrade deliberately with
`docker compose pull && docker compose up -d`. The `windmill-lsp` editor autocomplete
service is left out on purpose (it needs the Caddy `/ws` proxy from the official stack).

## The `rss_to_discord` flow

The first flow, brought over from the Mac. It is a template for the pipeline flows:

```
Input (feed_url, max_items)
  └─ a: fetch new items      Python - feedparser, dedupes via wmill state
      └─ b: for each item    loop over results.a
          └─ c: post to discord    retries 3x exponential
```

After provisioning, do these in the UI (both hosts):

1. **Change the admin password.** Bottom-left `User (admin)` -> set a real password.
2. **Paste your Discord webhook.** `Variables` -> `u/admin/discord_webhook` -> replace
   `REPLACE_ME_with_your_discord_webhook_url`. It is stored encrypted.
3. **Enable the schedule.** `Schedules` -> `u/admin/rss_to_discord` -> toggle on.
   Hourly (`0 0 * * * *`, Asia/Kathmandu), deliberately shipped **off**.

Things that will bite you:

- **The first run of any new dependency is slow** (~30 s while `feedparser` installs).
  It is cached after that. Don't mistake it for a hang.
- **State is per flow-step path.** Rename step `a` or move the flow and the dedupe
  history is gone; the next run re-seeds and posts nothing.
- **The first run after enabling the schedule posts nothing** - by design, so deploying
  doesn't dump the whole feed into the channel.
- **Windows jobs need a licence key first** (see the caveat above). `PYTHON_PATH`/
  `UV_PATH` are set by `AutoFlow.bat`; if a Python step fails on the Windows worker
  once a key is in place, `windmill\logs\windmill.log` is where the answer is.

## Phase 1: the research job (Windows)

Phase 1 needs the Claude Code **CLI** (the desktop app is a separate thing and does not
provide `claude -p`), plus the Nexlev MCP server registered locally. The Nexlev
connector attached to your claude.ai account is *not* visible to the CLI.

Steps 1-3 are **done**. Only step 4 is outstanding.

```powershell
# 1. DONE - CLI installed with npm's global prefix on D: (C: is nearly full).
#    The --allow-scripts flag lets the postinstall run; without it npm warns and
#    skips it. The install worked regardless, since claude.exe ships in the package.
npm config set prefix "D:\Claude Projects\AutoFlow\npm-global"
npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code

# 2. DONE - npm-global appended to the User PATH.
#    Already-open terminals will not see it; open a NEW one.

# 3. DONE - Nexlev registered at *user* scope, so it resolves from any directory.
#    (Plain `claude mcp add` writes local config tied to the current folder, which
#    breaks as soon as a script runs from somewhere else.)
claude mcp add --scope user --transport http nexlev https://prod.dashboard.nexlev.io/api/claude-mcp

# 4. TODO - two interactive logins. Neither can be scripted; both open a browser.
#    Open a NEW terminal and run `claude`, then:
#
#      a) /login  - signs the CLI in to your Claude account. This is SEPARATE
#                   from the desktop app's session; the CLI starts logged out
#                   even though the desktop app is signed in.
#      b) /mcp    - authenticate nexlev via OAuth.
#
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

Status as of 2026-08-27: `/login` **done** (plumbing check passes). The `nexlev`
server's `/mcp` OAuth is **still outstanding** - the probe above returns `NO_TOOL`.

`new-job.ps1` does not depend on PATH: if `claude` is not found there it falls back to
`npm-global\claude.cmd` directly, so it works from an already-open shell too.

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
