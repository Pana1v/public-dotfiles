#!/usr/bin/env bash
# Apply every module and install every listed package, no pickers.
#
#   ./apply-all.sh              the whole setup on this machine
#   ./apply-all.sh --dry-run    print every action, change nothing
#   ./apply-all.sh --serial     one module at a time, live output
#   ./apply-all.sh --preset professional --theme tron   save those choices too
#
# One sudo prompt up front. A module that fails skips only the modules that
# depend on it; the rest still run, and the summary lists what failed.
# Safe to re-run: modules already in place print ok.
set -euo pipefail
cd "$(dirname "$0")"

# The private submodule, claude-config and the Obsidian vault come over gh.
if ! gh auth status >/dev/null 2>&1; then
    echo "! gh is not logged in: private repo, claude-config and Obsidian vault are skipped (gh auth login)" >&2
fi

exec ./bootstrap.sh --all --all-packages --keep-going "$@"
