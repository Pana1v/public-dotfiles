#!/usr/bin/env bash
# Parse-check GJS ESM files with node. Catches typos before a shell restart.
rc=0
for f in "$@"; do
  tmp="$(mktemp --suffix=.mjs)"
  cp "$f" "$tmp"
  if out=$(node --check "$tmp" 2>&1); then
    echo "OK   $f"
  else
    echo "FAIL $f"; echo "$out" | head -8; rc=1
  fi
  rm -f "$tmp"
done
exit $rc
