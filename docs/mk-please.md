# mk-please

Serve any folder of markdown as a live MkDocs site in the active rice palette. Installed by the `mkdocs` module as `~/.local/bin/mk-please`.

```bash
mk-please [DIR=.] [PORT] [TITLE]
mk-please docs               # this repo's docs, live reload
mk-please ~/notes 8800 Notes
```

| Argument | Default |
|---|---|
| `DIR` | current folder |
| `PORT` | first free port from 8765, so several folders can be served at once |
| `TITLE` | the folder name |

It prints the URL and opens it in the browser when run from a terminal.

## What you get

| Feature | How |
|---|---|
| Rice colours | Read from `~/.config/kitty/current-theme.conf` at start |
| GitHub link | Title bar links the repo when `DIR` is in a git repo with a GitHub remote, at every screen width |
| PDF export | Two buttons per page: one continuous page, or A4 pages that never split a table, diagram, code block or callout |
| Copy markdown | Button copies the page source |
| Edit in Obsidian | Shown when `DIR` is inside an Obsidian vault, or linked into one |
| Mermaid zoom | Click a diagram to open it full screen; drag to pan, Esc closes |
| Index page | Generated, listing every page, when `DIR` has no `index.md` |
| Tags page | Generated from front matter `tags:` |
| Live reload | Also watches the targets of symlinked files |

Nothing is written into `DIR`: the config and theme overrides live under `$XDG_RUNTIME_DIR/mk-please/`. MkDocs and Material run through `uvx` on demand, pinned to mkdocs 1.6.1 and mkdocs-material 9.8.1.

!!! warning "Traps"
    - Colours are read once at start: restart it after `switch-theme.sh`.
    - It ignores a `mkdocs.yml` in `DIR` (nav, plugins). For this repo's published layout use `mkdocs serve` instead (see [Docs site](docs-site.md)).
    - The pins move together: the theme override depends on Material internals.
