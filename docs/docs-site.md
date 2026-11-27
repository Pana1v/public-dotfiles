# Docs site

These pages are plain markdown in `docs/`, built with MkDocs Material.

| Where | How |
|---|---|
| Hosted | <https://pana1v.github.io/public-dotfiles/>, rebuilt by `.github/workflows/docs.yml` on every push to `main` that touches `docs/` or `mkdocs.yml` |
| Local, rice colours | `mk-please docs` (the `mkdocs` module), live reload in the active palette |
| Local, as hosted | `uvx --from mkdocs==1.6.1 --with mkdocs-material==9.8.1 mkdocs serve` from the repo root |

`mk-please` ignores `mkdocs.yml`, so it shows the pages without this site's nav. Use `mkdocs serve` to check the nav and the blood styling exactly as published.

## Editing

1. Edit or add a page in `docs/`.
2. Add new pages to `nav:` in `mkdocs.yml`.
3. Check it builds cleanly: `uvx --from mkdocs==1.6.1 --with mkdocs-material==9.8.1 mkdocs build --strict`.
4. Push to `main`; the workflow publishes it.

`docs/modules.md` is a table of every `module.env`. Regenerate it when a module's `DESC` changes rather than editing it by hand.

!!! warning "Public"
    The site is public. Never put hostnames, IP addresses, emails or tokens in a page; those live in `private/`.
