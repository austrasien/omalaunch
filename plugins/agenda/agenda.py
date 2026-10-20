#!/usr/bin/env python3
"""agenda.py CONFIG CACHE_DIR DAYS — upcoming events from iCalendar feeds.

CONFIG is a JSON list of {"name", "url"} (Google Calendar's "secret address
in iCal format", or any .ics URL or file path). Feeds are fetched at most
every 10 minutes and the last good copy is used when offline. Prints a JSON
list of events from 30 minutes ago to DAYS days ahead, soonest first:
{title, start, end (ISO 8601 with offset), allDay, location, link, calendar}.
Recurring events (RRULE, EXDATE, moved or cancelled instances) are expanded.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from dateutil.rrule import rrulestr

def local_zone():
    """The system time zone as a real zone (with its DST rules), not today's offset."""
    name = os.environ.get("TZ", "").lstrip(":")
    if not name:
        link = os.path.realpath("/etc/localtime")
        name = link.split("/zoneinfo/", 1)[1] if "/zoneinfo/" in link else ""
    try:
        return ZoneInfo(name) if name else datetime.now().astimezone().tzinfo
    except Exception:
        return datetime.now().astimezone().tzinfo


LOCAL = local_zone()
LINK = re.compile(r"https://(?:meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com|[\w.-]*webex\.com|whereby\.com)/[^\s<>\"\\]+")


def fetch(url, cache_dir):
    if not re.match(r"^https?://", url):
        with open(os.path.expanduser(url), encoding="utf-8", errors="replace") as f:
            return f.read()
    path = os.path.join(cache_dir, hashlib.sha1(url.encode()).hexdigest()[:20] + ".ics")
    fresh = os.path.exists(path) and time.time() - os.path.getmtime(path) < 600
    if not fresh:
        try:
            data = subprocess.run(["curl", "-fsSL", "--max-time", "12", url], capture_output=True, check=True).stdout
            if b"BEGIN:VCALENDAR" in data:
                os.makedirs(cache_dir, exist_ok=True)
                with open(path + ".tmp", "wb") as f:
                    f.write(data)
                os.replace(path + ".tmp", path)
        except (subprocess.CalledProcessError, OSError):
            pass
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    return ""


def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).splitlines()


def unescape(v):
    return re.sub(r"\\([nN,;\\])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), v)


def parse_line(line):
    head, _, value = line.partition(":")
    parts = head.split(";")
    params = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        params[k.upper()] = v.strip('"')
    return parts[0].upper(), params, value


def to_dt(value, params):
    """→ (datetime aware, all_day)."""
    v = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", v):
        d = datetime.strptime(v[:8], "%Y%m%d")
        return d.replace(tzinfo=LOCAL), True
    if v.endswith("Z"):
        return datetime.strptime(v[:15], "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc), False
    naive = datetime.strptime(v[:15], "%Y%m%dT%H%M%S")
    tz = LOCAL
    if "TZID" in params:
        try:
            tz = ZoneInfo(params["TZID"])
        except Exception:
            tz = LOCAL
    return naive.replace(tzinfo=tz), False


def duration(v):
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", v.strip())
    if not m:
        return None
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, s = (int(x or 0) for x in m.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)


def events(text, name):
    out, cur = [], None
    for line in unfold(text):
        if line == "BEGIN:VEVENT":
            cur = {"exdates": [], "props": {}}
        elif line == "END:VEVENT" and cur is not None:
            out.append(cur)
            cur = None
        elif cur is not None and ":" in line:
            key, params, value = parse_line(line)
            if key == "EXDATE":
                for v in value.split(","):
                    cur["exdates"].append(to_dt(v, params)[0])
            elif key not in cur["props"]:
                cur["props"][key] = (params, value)
    for e in out:
        e["calendar"] = name
    return out


def expand(evs, start, end):
    overrides = {}
    for e in evs:
        if "RECURRENCE-ID" in e["props"]:
            p, v = e["props"]["RECURRENCE-ID"]
            overrides.setdefault(e["props"].get("UID", ({}, ""))[1], set()).add(to_dt(v, p)[0].astimezone(timezone.utc))
    result = []
    for e in evs:
        props = e["props"]
        if "DTSTART" not in props or props.get("STATUS", ({}, ""))[1].upper() == "CANCELLED":
            continue
        dtstart, all_day = to_dt(props["DTSTART"][1], props["DTSTART"][0])
        if "DTEND" in props:
            length = to_dt(props["DTEND"][1], props["DTEND"][0])[0] - dtstart
        elif "DURATION" in props:
            length = duration(props["DURATION"][1]) or timedelta(hours=1)
        else:
            length = timedelta(days=1) if all_day else timedelta(hours=1)
        starts = [dtstart]
        if "RRULE" in props and "RECURRENCE-ID" not in props:
            rule = props["RRULE"][1]
            if all_day or dtstart.tzinfo is not timezone.utc:
                # dateutil wants UNTIL in the same kind of time as DTSTART.
                def fix(m):
                    u, z = to_dt(m.group(1), {})
                    return "UNTIL=" + u.astimezone(dtstart.tzinfo).strftime("%Y%m%dT%H%M%S")
                rule = re.sub(r"UNTIL=([0-9TZ]+)", fix, rule)
            try:
                naive = dtstart.replace(tzinfo=None)
                r = rrulestr(rule, dtstart=naive, ignoretz=True)
                lo = (start - length).astimezone(dtstart.tzinfo).replace(tzinfo=None)
                hi = end.astimezone(dtstart.tzinfo).replace(tzinfo=None)
                starts = [s.replace(tzinfo=dtstart.tzinfo) for s in r.between(lo, hi, inc=True)]
            except Exception:
                starts = [dtstart]
            ex = {x.astimezone(timezone.utc) for x in e["exdates"]}
            moved = overrides.get(props.get("UID", ({}, ""))[1], set())
            starts = [s for s in starts if s.astimezone(timezone.utc) not in ex and s.astimezone(timezone.utc) not in moved]
        summary = unescape(props.get("SUMMARY", ({}, "(sans titre)"))[1])
        location = unescape(props.get("LOCATION", ({}, ""))[1])
        blob = " ".join(unescape(props.get(k, ({}, ""))[1]) for k in ("X-GOOGLE-CONFERENCE", "LOCATION", "DESCRIPTION", "URL"))
        m = LINK.search(blob)
        for s in starts:
            f = s + length
            if f <= start or s >= end:
                continue
            result.append({
                "title": summary, "start": s.astimezone(LOCAL).isoformat(), "end": f.astimezone(LOCAL).isoformat(),
                "allDay": all_day, "location": location, "link": m.group(0) if m else "", "calendar": e["calendar"],
            })
    result.sort(key=lambda x: (x["start"], x["title"]))
    return result


def main():
    config, cache_dir, days = sys.argv[1], sys.argv[2], int(sys.argv[3] if len(sys.argv) > 3 else 14)
    try:
        with open(config, encoding="utf-8") as f:
            calendars = json.load(f)
    except (OSError, ValueError):
        print("[]")
        return
    now = datetime.now(LOCAL)
    start, end = now - timedelta(minutes=30), now + timedelta(days=days)
    evs = []
    errors = []
    for c in calendars if isinstance(calendars, list) else []:
        if not isinstance(c, dict) or not c.get("url"):
            continue
        text = fetch(c["url"], cache_dir)
        if not text:
            errors.append(c.get("name") or c["url"][:40])
            continue
        evs.extend(expand(events(text, c.get("name") or "Calendar"), start, end))
    evs.sort(key=lambda x: (x["start"], x["title"]))
    print(json.dumps({"events": evs, "errors": errors}, ensure_ascii=False))


if __name__ == "__main__":
    main()
