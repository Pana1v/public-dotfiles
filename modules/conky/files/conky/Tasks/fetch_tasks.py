#!/usr/bin/env python3
"""Google Tasks (and any other task list) for the conky tasks panel.

Reads every enabled task list in evolution-data-server. GNOME Online Accounts
exposes a Google account's tasks there once Settings > Online Accounts >
Google > Tasks is on. Tab separated, one row per line:

  status  <ok|setup|error>  <message>
  task    <due epoch or 0>  <1 if done>  <list>  <title>

Open tasks come first, soonest due first, undated last. Tasks completed in the
last day follow, so a freshly ticked item stays visible for a while.
"""

import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

DONE_WINDOW = 24 * 3600
LOCAL_BACKENDS = {"local", ""}


# The panel fonts have no emoji, so they would draw as empty boxes.
EMOJI = re.compile("[\U0001F000-\U0001FAFF\u2190-\u27BF\u2900-\u2BFF\uFE00-\uFE0F\u200D]")


def clean(s):
    return re.sub(r"\s+", " ", EMOJI.sub("", s or "")).strip()


def due_epoch(comp):
    """Due date as epoch, 0 when the task has none. Date-only means local midnight."""
    import datetime
    due = comp.get_due()
    if due is None or due.is_null_time():
        return 0
    if due.is_date():
        return int(datetime.datetime(due.get_year(), due.get_month(), due.get_day()).timestamp())
    return due.as_timet()


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

    registry = EDataServer.SourceRegistry.new_sync(None)
    sources = [s for s in registry.list_sources(EDataServer.SOURCE_EXTENSION_TASK_LIST) if s.get_enabled()]

    def backend(s):
        return s.get_extension(EDataServer.SOURCE_EXTENSION_TASK_LIST).get_backend_name() or ""

    if "--list" in sys.argv:
        for s in sources:
            print(s.get_uid(), "|", s.get_display_name(), "|", backend(s))
        return

    DONE = ICalGLib.PropertyStatus.COMPLETED
    CANCELLED = ICalGLib.PropertyStatus.CANCELLED
    now = int(time.time())
    open_tasks, done_tasks, errors = [], [], []

    def read_list(source):
        """One list's (open, done, error), run in its own thread: each Google list
        takes several seconds to connect, so reading them one by one is slow."""
        open_t, done_t, err = [], [], None
        name = source.get_display_name()
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.TASKS, 15, None)
            ok, comps = client.get_object_list_as_comps_sync("#t", None)
            for ec in comps if ok else []:
                comp = ec.get_icalcomponent()
                status = comp.get_status()
                if status == CANCELLED:
                    continue
                title = clean(comp.get_summary()) or "(no title)"
                if status == DONE:
                    finished = comp.get_completed()
                    when = finished.as_timet() if finished is not None and not finished.is_null_time() else 0
                    if now - when <= DONE_WINDOW:
                        done_t.append((0, 1, name, title))
                else:
                    open_t.append((due_epoch(comp), 0, name, title))
        except Exception as exc:  # one broken list must not hide the rest
            err = f"{name}: {exc}"
        return open_t, done_t, err

    with ThreadPoolExecutor(max_workers=len(sources) or 1) as pool:
        for open_t, done_t, err in pool.map(read_list, sources):
            open_tasks += open_t
            done_tasks += done_t
            if err:
                errors.append(err)

    online = any(backend(s) not in LOCAL_BACKENDS for s in sources)
    everything = sorted(open_tasks, key=lambda t: (t[0] == 0, t[0], t[3])) + done_tasks
    if errors and not everything:
        print("status\terror\t" + clean(errors[0])[:120])
    elif not online:
        print("status\tsetup\tconnect Google in Settings > Online Accounts")
    else:
        print("status\tok\t")
    for t in everything:
        print("task\t" + "\t".join(str(x) for x in t))


if __name__ == "__main__":
    main()
