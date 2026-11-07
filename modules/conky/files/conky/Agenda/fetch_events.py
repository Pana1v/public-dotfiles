#!/usr/bin/env python3
"""Upcoming events for the conky agenda panel, from GNOME's calendars.

Reads every enabled calendar in evolution-data-server, which is where GNOME
Online Accounts puts a Google account (Settings > Online Accounts > Google >
Calendar on). Recurring events are expanded by libecal. Output is tab
separated, one row per line:

  status  <ok|setup|error>  <message>
  ev      <start epoch>  <end epoch>  <1 if all day>  <calendar>  <1 if video call>  <title>  <location>

"setup" means no online calendar is connected yet. The window runs from the
start of today to the end of the day after next, and events that already
ended are left out. `--list` prints the calendars instead, for debugging.
"""

import datetime
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

DAYS = 3
MEETING = re.compile(r"meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com", re.I)
LOCAL_BACKENDS = {"local", "contacts", ""}


# The panel fonts have no emoji, so they would draw as empty boxes.
EMOJI = re.compile("[\U0001F000-\U0001FAFF\u2190-\u27BF\u2900-\u2BFF\uFE00-\uFE0F\u200D]")


def clean(s):
    return re.sub(r"\s+", " ", EMOJI.sub("", s or "")).strip()


def epoch(t):
    """ICalTime to epoch. Date-only values are local midnight."""
    if t.is_date():
        return int(datetime.datetime(t.get_year(), t.get_month(), t.get_day()).timestamp())
    return t.as_timet()


def main():
    try:
        import gi
        gi.require_version("EDataServer", "1.2")
        gi.require_version("ECal", "2.0")
        gi.require_version("ICalGLib", "3.0")
        from gi.repository import ECal, EDataServer, ICalGLib
    except (ImportError, ValueError):
        print("status\tsetup\tinstall gir1.2-ecal-2.0")
        return

    CANCELLED = ICalGLib.PropertyStatus.CANCELLED
    registry = EDataServer.SourceRegistry.new_sync(None)
    sources = [s for s in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR) if s.get_enabled()]

    def backend(s):
        return s.get_extension(EDataServer.SOURCE_EXTENSION_CALENDAR).get_backend_name() or ""

    if "--list" in sys.argv:
        for s in sources:
            print(s.get_uid(), "|", s.get_display_name(), "|", backend(s))
        return

    midnight = datetime.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    start = int(midnight.timestamp())
    end = int((midnight + datetime.timedelta(days=DAYS)).timestamp())
    now = int(time.time())

    events, errors = {}, []

    def read_calendar(source):
        """Collect one calendar's instances; threads because each online calendar
        takes seconds to connect."""
        name = source.get_display_name()

        def collect(comp, istart, iend, *_rest, name=name):
            if comp.get_status() == CANCELLED:
                return True
            s, e = epoch(istart), epoch(iend)
            if e <= now:
                return True
            title = clean(comp.get_summary()) or "(no title)"
            where = clean(comp.get_location())
            video = int(bool(MEETING.search(where) or MEETING.search(comp.get_description() or "")))
            events[(s, title)] = (s, e, int(istart.is_date()), name, video, title, where)
            return True

        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, 15, None)
            client.generate_instances_sync(start, end, None, collect, None)
        except Exception as err:  # one broken calendar must not hide the rest
            errors.append(f"{name}: {err}")

    with ThreadPoolExecutor(max_workers=len(sources) or 1) as pool:
        list(pool.map(read_calendar, sources))

    online = any(backend(s) not in LOCAL_BACKENDS for s in sources)
    if errors and not events:
        print("status\terror\t" + clean(errors[0])[:120])
    elif not online:
        print("status\tsetup\tconnect Google in Settings > Online Accounts")
    else:
        print("status\tok\t")
    for ev in sorted(events.values()):
        print("ev\t" + "\t".join(str(x) for x in ev))


if __name__ == "__main__":
    main()
