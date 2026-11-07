#!/usr/bin/env python3
"""Open PRs for the conky GithubPRs panel, via the gh CLI's keyring login.

One GraphQL call covers both lists, so review decision and CI rollup
come along (gh search prs can't return either).

Output: EMPTY when there are no PRs, else tab-separated, one PR per line:
  kind (M = mine, R = review requested), repo#number, draft (1/0),
  review (APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED / ""),
  ci (SUCCESS / FAILURE / ERROR / PENDING / ""), relative_time, title
Prints nothing on failure so the caller keeps its last-good cache.

Whose PRs: GITHUB_USER from the environment or ~/.config/dotfiles/local.env
(e.g. GITHUB_USER=Pan-Navigator). That account's own gh token is used, so the
active gh account doesn't matter; it needs one `gh auth login` as that user.
Unset means the active gh account (@me).
"""

import json
import os
import re
import subprocess
from datetime import datetime, timezone

LIMIT = 8

QUERY = """
query($mine: String!, $review: String!, $limit: Int!) {
  mine: search(query: $mine, type: ISSUE, first: $limit) { nodes { ...pr } }
  review: search(query: $review, type: ISSUE, first: $limit) { nodes { ...pr } }
}
fragment pr on PullRequest {
  number title isDraft updatedAt reviewDecision
  repository { name }
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
}
"""

SEARCHES = {
    "mine": "is:pr is:open author:@me sort:updated-desc",
    "review": "is:pr is:open review-requested:@me sort:updated-desc",
}


def relative_time(iso_ts: str) -> str:
    dt = datetime.fromisoformat(iso_ts.replace("Z", "+00:00"))
    seconds = (datetime.now(timezone.utc) - dt).total_seconds()
    if seconds < 3600:
        return f"{int(seconds // 60)}m ago"
    if seconds < 86400:
        return f"{int(seconds // 3600)}h ago"
    return f"{int(seconds // 86400)}d ago"


def ci_state(pr: dict) -> str:
    commits = pr["commits"]["nodes"]
    if not commits or not commits[0]["commit"]["statusCheckRollup"]:
        return ""
    return commits[0]["commit"]["statusCheckRollup"]["state"]


def github_user() -> str:
    user = os.environ.get("GITHUB_USER", "")
    if not user:
        try:
            with open(os.path.expanduser("~/.config/dotfiles/local.env")) as f:
                for line in f:
                    m = re.match(r"\s*GITHUB_USER\s*=\s*[\"']?([\w-]+)", line)
                    if m:
                        user = m.group(1)
        except OSError:
            pass
    return user


def main() -> None:
    user = github_user()
    env = os.environ.copy()
    if user:
        # That user's token; if they never logged in, fall back to the active
        # account, which still sees the user's PRs in public repos.
        tok = subprocess.run(["gh", "auth", "token", "--user", user],
                             capture_output=True, text=True).stdout.strip()
        if tok:
            env["GH_TOKEN"] = tok
    who = user or "@me"
    cmd = [
        "gh", "api", "graphql",
        "-f", f"query={QUERY}",
        "-f", f"mine={SEARCHES['mine'].replace('@me', who)}",
        "-f", f"review={SEARCHES['review'].replace('@me', who)}",
        "-F", f"limit={LIMIT}",
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20, check=True, env=env).stdout
        data = json.loads(out)["data"]
    except Exception:
        return

    if not data["mine"]["nodes"] and not data["review"]["nodes"]:
        print("EMPTY")
        return

    for kind, key in (("M", "mine"), ("R", "review")):
        for pr in data[key]["nodes"]:
            print(
                f"{kind}\t{pr['repository']['name']}#{pr['number']}\t"
                f"{int(pr['isDraft'])}\t{pr['reviewDecision'] or ''}\t{ci_state(pr)}\t"
                f"{relative_time(pr['updatedAt'])}\t{pr['title'].replace(chr(9), ' ')}"
            )


if __name__ == "__main__":
    main()
