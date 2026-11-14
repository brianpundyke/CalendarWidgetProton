#!/usr/bin/env python3
"""Fetch an iCal feed and print upcoming events as JSON for the Proton Agenda widget.

The feed URL comes from --url, or, when that is empty, from KOrganizer's
Akonadi iCal subscription (~/.config/akonadi_ical_resource_*rc). A copy of the
last good download is cached so the widget still shows events while offline.
"""
import argparse
import datetime as dt
import glob
import json
import os
import subprocess
import sys
import urllib.request

CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "proton-agenda"
)
CACHE_FILE = os.path.join(CACHE_DIR, "calendar.ics")
CONFIG_DIR = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))


def out(payload):
    print(json.dumps(payload, ensure_ascii=False))
    sys.exit(0)


def url_from_akonadi():
    """Return the Path of the first Akonadi iCal resource that points at a web URL."""
    for rc in sorted(glob.glob(os.path.join(CONFIG_DIR, "akonadi_ical_resource_*rc"))):
        name = os.path.basename(rc)
        try:
            path = subprocess.run(
                ["kreadconfig6", "--file", name, "--group", "General", "--key", "Path"],
                capture_output=True, text=True, timeout=10,
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            path = ""
        if path.startswith(("http://", "https://", "webcal://")):
            return path
    return ""


def fetch(url):
    """Download the feed, falling back to the cache. Returns (text, stale, error)."""
    url = "https://" + url[len("webcal://"):] if url.startswith("webcal://") else url
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "proton-agenda-plasmoid"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read().decode("utf-8", errors="replace")
        if "BEGIN:VCALENDAR" not in data[:200]:
            raise ValueError("response is not an iCalendar file")
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
            f.write(data)
        os.replace(tmp, CACHE_FILE)
        return data, False, ""
    except Exception as e:  # network down, HTTP error, bad data…
        err = str(e)
        if os.path.exists(CACHE_FILE):
            with open(CACHE_FILE, encoding="utf-8") as f:
                return f.read(), True, err
        return None, True, err


def to_local(value):
    """Convert a DTSTART/DTEND value to (local naive datetime, is_all_day)."""
    if isinstance(value, dt.datetime):
        if value.tzinfo is not None:
            value = value.astimezone().replace(tzinfo=None)
        return value, False
    return dt.datetime.combine(value, dt.time()), True


def text(component, key):
    v = component.get(key)
    return str(v).strip() if v is not None else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--url", default="")
    args = ap.parse_args()

    try:
        import icalendar
        import recurring_ical_events
    except ImportError as e:
        out({"error": f"Missing Python library ({e.name}). Re-run install.sh.", "days": []})

    url = args.url.strip() or url_from_akonadi()
    if not url:
        out({"error": "No calendar link found. Set one in the widget settings.", "days": []})

    data, stale, err = fetch(url)
    if data is None:
        out({"error": f"Could not download calendar: {err}", "days": []})

    try:
        cal = icalendar.Calendar.from_ical(data)
    except Exception as e:
        out({"error": f"Could not read calendar: {e}", "days": []})

    today = dt.date.today()
    days = max(1, args.days)
    range_start = dt.datetime.combine(today, dt.time())
    range_end = range_start + dt.timedelta(days=days)

    buckets = {today + dt.timedelta(days=i): [] for i in range(days)}
    for ev in recurring_ical_events.of(cal).between(range_start, range_end):
        if text(ev, "STATUS").upper() == "CANCELLED":
            continue
        start, all_day = to_local(ev["DTSTART"].dt)
        if ev.get("DTEND") is not None:
            end, _ = to_local(ev["DTEND"].dt)
        elif ev.get("DURATION") is not None:
            end = start + ev["DURATION"].dt
        else:
            end = start + (dt.timedelta(days=1) if all_day else dt.timedelta())
        if end < start:
            end = start

        item = {
            "title": text(ev, "SUMMARY") or "(no title)",
            "location": text(ev, "LOCATION"),
            "allDay": all_day,
            "start": start.isoformat(timespec="minutes"),
            "end": end.isoformat(timespec="minutes"),
        }
        # Place the event on every day in range that it overlaps.
        d = start.date()
        last = (end - dt.timedelta(microseconds=1)).date() if end > start else d
        while d <= last:
            if d in buckets:
                buckets[d].append(item)
            d += dt.timedelta(days=1)

    result = []
    for d in sorted(buckets):
        evs = sorted(buckets[d], key=lambda e: (not e["allDay"], e["start"], e["title"].lower()))
        if evs:
            result.append({"date": d.isoformat(), "events": evs})

    out({
        "error": "",
        "stale": stale,
        "staleReason": err if stale else "",
        "updated": dt.datetime.now().isoformat(timespec="minutes"),
        "days": result,
    })


if __name__ == "__main__":
    main()
