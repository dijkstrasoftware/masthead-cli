# masthead_cli

A standalone preview server for [Masthead](https://masthead.site) themes.

Run `masthead preview` inside a theme directory and see exactly how your
theme will render on the live platform — no database, no Phoenix app, no
upload step. It reproduces Masthead's real render pipeline:

- `manifest.json` parsing + validation (identical rules to upload)
- the **Solid/Liquid sandbox** with the same custom filters
  (`asset_url`, `strftime`, `iso8601`)
- token → `:root { --… }` **CSS injection** (file tokens wrapped in
  `url(…)`, empty file tokens skipped)
- the **content pipeline** (Earmark markdown + the same HTML sanitizer)
- per-page **metadata** merged against the manifest schema
- the exact route table and controller logic of the public site

The renderer, presenter, manifest, sandbox, filters, CSS sanitizer and
content scrubber are faithful copies of the host application's modules, so
a template that previews correctly here renders the same way in
production.

## Install

### Homebrew (recommended)

```sh
brew install joeridijkstra/tap/masthead
```

To track the latest `main` instead of the newest release:

```sh
brew install --HEAD joeridijkstra/tap/masthead
```

### From source

Requires Elixir (`~> 1.15`; developed on 1.18 / OTP 28).

```sh
git clone https://github.com/JoeriDijkstra/masthead-cli ~/personal/masthead_cli
cd ~/personal/masthead_cli
mix deps.get
mix escript.build          # produces ./masthead
```

Put it on your `PATH`:

```sh
# option A: symlink the built binary
ln -s "$PWD/masthead" ~/.local/bin/masthead

# option B: install into ~/.mix/escripts (then add it to PATH)
mix escript.install
```

## Usage

```sh
masthead create my-theme         # scaffold a new theme from the template

cd my-theme
masthead preview                 # serves http://localhost:4010
masthead preview --port 4020     # pick a port
masthead preview --dir ../other  # point elsewhere

masthead validate                # check manifest + templates, no server
masthead package                 # zip the theme to ~/Desktop
masthead doctor                  # report Erlang/Elixir versions, flag mismatches
masthead help
```

## Creating a theme

`masthead create NAME` scaffolds a new theme in a `NAME/` directory by
cloning the [theme template](https://github.com/JoeriDijkstra/masthead-template)
— a complete, valid starter (`manifest.json`, `theme.css`, and the six
templates). The template's git history is removed so you start clean, and
the manifest's `name`/`slug` are set from `NAME`:

```sh
masthead create my-theme
cd my-theme
masthead preview
```

The directory name seeds the slug (lowercased, hyphenated), so
`masthead create "My Theme"` produces slug `my-theme` and name `My Theme`.
`create` requires `git` on your PATH and won't overwrite a non-empty
directory.

## Packaging

`masthead package` bundles the theme into an installable Masthead theme
zip — exactly the files the platform consumes, and nothing else:

```
manifest.json
theme.css
templates/{layout,index,post,page,blog,not_found}.liquid
assets/…            (only whitelisted file types, no symlinks)
```

Dev-only files (`preview/`, `preview.json`, `README.md`, `.git`,
`.DS_Store`, stray `*.zip`, …) are left out. The theme is validated first
(manifest + all six templates must parse), so a broken theme won't
package, and the platform's upload limits (5 MB zip, 25 MB unpacked, 200
files) plus the reserved-slug / asset-type rules are checked up front and
reported as warnings.

```sh
masthead package                     # -> ~/Desktop/<slug>-<version>.zip
masthead package --out ~/Downloads   # into a directory
masthead package -o ./dist/theme.zip # exact file path
masthead package --dir ~/themes/acme # package a theme elsewhere
```

The output path (`--out` / `-o`, or a bare path argument) is a `.zip` file
when it ends in `.zip`, otherwise a directory the zip is dropped into.
With no path, it writes `~/Desktop/<slug>-<version>.zip` (falling back to
your home directory if there's no Desktop).

`preview` re-reads the theme on **every request**, so edits to templates,
`theme.css`, `manifest.json`, or your preview content show up on refresh —
no restart. If a template fails to parse or render, the browser shows a
diagnostic page (and the console prints the error) so you can fix and
refresh in place.

### Live token inspector

While previewing, a floating **gear button** sits in the bottom-right
corner of every page (you can also toggle the panel with the **backtick
`` ` ``** key or **Cmd/Ctrl+E**). It opens a sidebar with a control for
every token your `manifest.json` declares — a colour picker for `color`,
a dropdown for `select`, a text field for everything else.

Editing a control updates the matching CSS custom property **live**, with
no reload, so you can dial in an accent colour or page width by eye.

This is a dev-only convenience: the preview server injects the overlay
into the rendered page (production never touches theme output). Edits are
**ephemeral** — nothing is written to disk, and a refresh resets to your
manifest / `preview.json` values. Only tokens used as CSS variables update
live; a token consumed in template logic (e.g. an email in a `mailto:`)
is baked into the HTML at render time and won't change here.

Disable it with `masthead preview --no-inspector`.

### Theme layout

The directory must look like a Masthead theme:

```
manifest.json
theme.css
templates/
  layout.liquid      index.liquid     post.liquid
  page.liquid        blog.liquid      not_found.liquid
assets/              (optional — images, fonts, extra css)
```

Files under `assets/` are served at `/assets/...`, matching
`{{ 'logo.png' | asset_url: theme.asset_base }}`.

## Sample content

With no configuration, the preview ships realistic sample content (a small
blog with a few posts, an About page and a Blog page) so every theme has
something to render. Customise it by dropping any of these into the theme
directory:

### `preview.json`

```json
{
  "site": {
    "name": "Acme Co.",
    "title": "Acme — we make things",
    "description": "A short site description.",
    "slug": "acme",
    "css_overrides": ".intro { letter-spacing: -0.02em; }",
    "homepage": "home"
  },
  "tokens": { "accent": "#d9480f", "max_width": "1120px" }
}
```

- `site.homepage` is the **slug** of the page to serve at `/` (just like
  setting a homepage in the Masthead admin). Omit it to render the
  theme's `index` template (post list) at `/`.
- `tokens` override the manifest defaults — exactly the per-site
  customisation site owners get. Unknown keys are ignored.

### Posts and pages as Markdown files

Drop one file per post/page into `preview/posts/` and `preview/pages/`,
with an optional JSON **front matter** block:

```markdown
---
{ "title": "About", "slug": "about", "format": "markdown",
  "metadata": { "layout": "wide" }, "show_in_nav": true }
---
## About us

Markdown body goes here.
```

- Front-matter keys mirror the platform's fields. Anything omitted is
  inferred from the filename (`about.md` → slug `about`, title `About`).
- `published_at` (posts) accepts an ISO-8601 datetime
  (`2026-01-15T09:00:00Z`) or a date (`2026-01-15`).
- Posts are ordered newest-first; pages are ordered by title — matching
  the live site's queries.
- A `.html` file is treated as `format: "html"` (sanitised, not parsed as
  markdown). A page with `"format": "blog"` renders through the `blog`
  template with the post list.

Files in `preview/posts` / `preview/pages` take precedence over inline
`posts` / `pages` arrays you may also put in `preview.json`.

## Variables available to templates

Same contract as production:

| Variable | Shape |
| --- | --- |
| `site` | `name`, `title`, `description`, `slug`, `css_overrides`, `homepage_slug` |
| `theme` | `name`, `slug`, `version`, `asset_base`, `tokens.<key>`, `css` |
| `post` | `title`, `slug`, `excerpt`, `published_at`, `url` |
| `posts` | list of the above |
| `page` | `title`, `slug`, `format`, `url`, `metadata.<key>` |
| `pages` | list of the above (nav: homepage + `show_in_nav:false` excluded) |
| `body_html` | rendered, sanitised post/page body (emit raw, do not `escape`) |
| `content` | (layout only) the rendered inner template |

Solid does **not** auto-escape — call `| escape` on user strings, exactly
as in production.

### Differences from production (by design)

- **File tokens**: production stores an upload *id* and resolves it to a
  URL via the uploads table. There are no uploads in preview, so a `file`
  token's value is used verbatim as a URL/path (e.g. set
  `"favicon": "/assets/favicon.ico"` in `preview.json` `tokens`). Empty
  file tokens emit no CSS declaration, just like production.

## Development

```sh
mix test                      # 33 tests covering the full pipeline
mix format
mix compile --warnings-as-errors
```
