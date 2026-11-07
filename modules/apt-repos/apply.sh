#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
ROOT="$DOTFILES/modules/apt-repos/files/root"

# Sources store the release as @CODENAME@ (snapshot.sh), so one copy serves
# every Ubuntu base. UBUNTU_CODENAME, not VERSION_CODENAME: Zorin sets its own.
CODENAME="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# install(1) per file, never rsync to /: rsync -a would copy the repo's
# directory ownership onto /etc and /usr.
while read -r f; do
    dst="/${f#"$ROOT"/}"
    src="$f"

    # Render sources only; keyrings are binary.
    if [[ "$dst" == /etc/apt/sources.list.d/* ]]; then
        src="$TMP/$(basename "$f")"
        sed "s/@CODENAME@/$CODENAME/g" "$f" > "$src"
    fi

    if cmp -s "$src" "$dst"; then
        log "ok      $dst"
        continue
    fi
    run sudo install -D -m 644 -o root -g root "$src" "$dst"
    log "install $dst"
done < <(find "$ROOT" -type f)

run sudo apt-get update
