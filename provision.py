#!/usr/bin/env python3
"""Create the rss_to_discord flow (and its variable + schedule) over the Windmill API.

Idempotent: re-running updates the flow in place instead of erroring.
Stdlib only — no pip install needed on the host.

    python3 provision.py                  # against http://localhost:8000
    WM_PASSWORD=yournewpassword python3 provision.py
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("WM_BASE", "http://localhost:8000")
EMAIL = os.environ.get("WM_EMAIL", "admin@windmill.dev")
PASSWORD = os.environ.get("WM_PASSWORD", "changeme")
TIMEZONE = os.environ.get("WM_TIMEZONE", "Asia/Kathmandu")

FLOW_PATH = "u/admin/rss_to_discord"
VAR_PATH = "u/admin/discord_webhook"
HERE = pathlib.Path(__file__).parent


def call(method, path, body=None, token=None, raw=False):
    req = urllib.request.Request(BASE + path, method=method)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data, timeout=30) as r:
            text = r.read().decode()
            if raw or not text:
                return r.status, text
            # Several endpoints answer with a bare string (a token, "Created X").
            try:
                return r.status, json.loads(text)
            except json.JSONDecodeError:
                return r.status, text
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except urllib.error.URLError as e:
        sys.exit(f"cannot reach {BASE}: {e.reason}\nIs the stack up?  docker compose ps")


def main():
    status, token = call("POST", "/api/auth/login", {"email": EMAIL, "password": PASSWORD}, raw=True)
    if status != 200:
        sys.exit(
            f"login failed ({status}): {token}\n"
            "If you already changed the admin password, pass it: WM_PASSWORD=... python3 provision.py"
        )
    token = token.strip().strip('"')
    print("logged in as", EMAIL)

    status, workspaces = call("GET", "/api/workspaces/list", token=token)
    if status != 200:
        sys.exit(f"could not list workspaces ({status}): {workspaces}")
    ids = [w["id"] for w in workspaces]
    ws = os.environ.get("WM_WORKSPACE") or ("main" if "main" in ids else (ids[0] if ids else "main"))
    if ws not in ids:
        # Fresh instance: Windmill ships with no workspace at all.
        status, resp = call("POST", "/api/workspaces/create", {"id": ws, "name": ws}, token=token)
        if status != 200:
            sys.exit(f"could not create workspace {ws} ({status}): {resp}")
        print("workspace created:", ws)
    else:
        print("workspace:", ws)

    # 1. Secret variable, created empty-ish so the flow fails loudly rather than
    #    silently posting nowhere. You paste the real webhook in the UI.
    status, _ = call("GET", f"/api/w/{ws}/variables/get/{VAR_PATH}", token=token)
    if status == 200:
        print("variable exists, leaving it alone:", VAR_PATH)
    else:
        status, resp = call("POST", f"/api/w/{ws}/variables/create", {
            "path": VAR_PATH,
            "value": "REPLACE_ME_with_your_discord_webhook_url",
            "is_secret": True,
            "description": "Discord channel webhook used by rss_to_discord",
        }, token=token)
        print("variable created" if status in (200, 201) else f"variable create failed ({status}): {resp}")

    # 2. The flow itself.
    fetch = (HERE / "flow" / "fetch_new_items.py").read_text()
    post = (HERE / "flow" / "post_to_discord.py").read_text()

    value = {
        "modules": [
            {
                "id": "a",
                "summary": "fetch new items",
                "value": {
                    "type": "rawscript",
                    "language": "python3",
                    "content": fetch,
                    "input_transforms": {
                        "feed_url": {"type": "javascript", "expr": "flow_input.feed_url"},
                        "max_items": {"type": "javascript", "expr": "flow_input.max_items"},
                    },
                },
            },
            {
                "id": "b",
                "summary": "post each item",
                "value": {
                    "type": "forloopflow",
                    "iterator": {"type": "javascript", "expr": "results.a"},
                    "skip_failures": False,
                    "parallel": False,
                    "modules": [
                        {
                            "id": "c",
                            "summary": "post to discord",
                            # Network calls get retried; one Discord blip shouldn't
                            # fail the run and lose the dedupe state.
                            "retry": {"exponential": {
                                "attempts": 3, "multiplier": 2, "seconds": 2, "random_factor": 0,
                            }},
                            "value": {
                                "type": "rawscript",
                                "language": "python3",
                                "content": post,
                                "input_transforms": {
                                    "item": {"type": "javascript", "expr": "flow_input.iter.value"},
                                    "webhook_variable": {"type": "static", "value": VAR_PATH},
                                },
                            },
                        }
                    ],
                },
            },
        ]
    }

    schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "order": ["feed_url", "max_items"],
        "properties": {
            "feed_url": {"type": "string", "default": "https://hnrss.org/frontpage",
                         "description": "Any RSS/Atom URL"},
            "max_items": {"type": "integer", "default": 5,
                          "description": "Cap per run so a burst can't flood the channel"},
        },
        "required": [],
    }

    body = {
        "path": FLOW_PATH,
        "summary": "RSS to Discord",
        "description": "Checks a feed, posts items it hasn't seen before to a Discord channel.",
        "value": value,
        "schema": schema,
    }

    status, resp = call("GET", f"/api/w/{ws}/flows/get/{FLOW_PATH}", token=token)
    if status == 200:
        status, resp = call("POST", f"/api/w/{ws}/flows/update/{FLOW_PATH}", body, token=token)
        action = "updated"
    else:
        status, resp = call("POST", f"/api/w/{ws}/flows/create", body, token=token)
        action = "created"
    if status not in (200, 201):
        sys.exit(f"flow {action[:-1]}e failed ({status}): {resp}")
    print(f"flow {action}: {FLOW_PATH}")

    # 3. Hourly schedule, left OFF until the webhook is filled in.
    sched = {
        "path": FLOW_PATH,
        "schedule": "0 0 * * * *",   # leading field is SECONDS
        "timezone": TIMEZONE,
        "script_path": FLOW_PATH,
        "is_flow": True,
        "args": {"feed_url": "https://hnrss.org/frontpage", "max_items": 5},
        "enabled": False,
    }
    status, resp = call("GET", f"/api/w/{ws}/schedules/get/{FLOW_PATH}", token=token)
    if status == 200:
        print("schedule already exists, leaving it alone")
    else:
        status, resp = call("POST", f"/api/w/{ws}/schedules/create", sched, token=token)
        print("schedule created (disabled)" if status in (200, 201)
              else f"schedule create failed ({status}): {resp}")

    print(f"\nopen {BASE}/flows/get/{FLOW_PATH}?workspace={ws}")


if __name__ == "__main__":
    main()
