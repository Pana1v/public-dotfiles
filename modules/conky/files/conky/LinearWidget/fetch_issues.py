#!/usr/bin/env python3
"""Fetch for the standalone large Linear conky widget.

Same stdlib-only, parse-the-secrets-file-directly approach as the earlier
small card (see history): runs via conky's ${exec}, never io.popen from Lua.

Output: one line per issue, tab-separated:
  identifier, state_type, state_name, priority_label, project_name,
  relative_time, title
Prints nothing on failure so the caller keeps its last-good cache.
"""

import json
import os
import re
import urllib.request
from datetime import datetime, timezone

ENV_PATH = os.path.expanduser("~/.config/secrets/linear.env")
LIMIT = 12

PRIORITY_LABEL = {0: "", 1: "Urgent", 2: "High", 3: "Medium", 4: "Low"}


def read_api_key() -> str | None:
    try:
        with open(ENV_PATH) as f:
            for line in f:
                m = re.match(r'^\s*export\s+LINEAR_API_KEY=(.+?)\s*$', line)
                if m:
                    return m.group(1).strip().strip('"').strip("'")
    except OSError:
        pass
    return os.environ.get("LINEAR_API_KEY")


def relative_time(iso_ts: str) -> str:
    try:
        dt = datetime.fromisoformat(iso_ts.replace("Z", "+00:00"))
    except ValueError:
        return ""
    delta = datetime.now(timezone.utc) - dt
    seconds = delta.total_seconds()
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{int(seconds // 60)}m ago"
    if seconds < 86400:
        return f"{int(seconds // 3600)}h ago"
    if seconds < 604800:
        return f"{int(seconds // 86400)}d ago"
    return f"{int(seconds // 604800)}w ago"


def main() -> None:
    api_key = read_api_key()
    if not api_key:
        return

    query = """
    query ActiveAssignedIssues($limit: Int!) {
      viewer {
        assignedIssues(
          filter: { state: { type: { nin: ["completed", "canceled"] } } }
          orderBy: updatedAt
          first: $limit
        ) {
          nodes {
            identifier
            title
            priority
            updatedAt
            state { name type }
            project { name }
          }
        }
      }
    }
    """
    body = json.dumps({"query": query, "variables": {"limit": LIMIT}}).encode()
    req = urllib.request.Request(
        "https://api.linear.app/graphql",
        data=body,
        headers={"Content-Type": "application/json", "Authorization": api_key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:  # noqa: S310
            data = json.loads(resp.read())
        issues = data["data"]["viewer"]["assignedIssues"]["nodes"]
    except Exception:
        return

    for issue in issues:
        identifier = issue["identifier"]
        state_type = issue["state"]["type"]
        state_name = issue["state"]["name"]
        priority_label = PRIORITY_LABEL.get(issue.get("priority") or 0, "")
        project = issue["project"]["name"] if issue.get("project") else ""
        rel_time = relative_time(issue["updatedAt"])
        title = issue["title"].replace("\t", " ")
        print(
            f"{identifier}\t{state_type}\t{state_name}\t{priority_label}\t"
            f"{project}\t{rel_time}\t{title}"
        )


if __name__ == "__main__":
    main()
