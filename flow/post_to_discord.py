import requests
import wmill


def main(item: dict, webhook_variable: str = "u/admin/discord_webhook"):
    webhook = wmill.get_variable(webhook_variable)
    if not webhook or webhook.startswith("REPLACE_ME"):
        raise RuntimeError(
            f"variable {webhook_variable} is unset — paste your Discord webhook URL "
            "into it from the Variables page"
        )

    r = requests.post(
        webhook,
        json={"content": f"**{item['title']}**\n{item['link']}"},
        timeout=15,
    )
    r.raise_for_status()
    return item["link"]
