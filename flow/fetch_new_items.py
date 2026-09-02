import feedparser
import wmill


def main(feed_url: str = "https://hnrss.org/frontpage", max_items: int = 5):
    """Return feed entries not seen on a previous run.

    State is a list of recently seen links, stored by Windmill per step.
    The very first run seeds that list and returns nothing, so deploying this
    doesn't dump the whole front page into the channel at once.
    """
    feed = feedparser.parse(feed_url)
    if getattr(feed, "bozo", 0) and not feed.entries:
        raise RuntimeError(f"could not parse feed: {getattr(feed, 'bozo_exception', 'unknown')}")

    links = [e.link for e in feed.entries]
    seen = wmill.get_state()

    if seen is None:
        wmill.set_state(links)
        return []

    new = [
        {"title": e.title, "link": e.link}
        for e in feed.entries
        if e.link not in seen
    ]

    # Keep a bounded window: long enough that an item falling off the feed and
    # reappearing doesn't re-post, short enough that state stays small.
    wmill.set_state((links + seen)[:200])
    return new[:max_items]
