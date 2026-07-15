# masthead_cli

A local theme editor and preview server for [Masthead](https://masthead.site).

Run `masthead preview` inside a theme directory: your theme renders in a
frame, and a **settings sidebar** beside it shows every token your
`manifest.json` declares and every setting the page you're looking at
declares. Change one and the page re-renders — no database, no Phoenix app,
no upload step.

It reproduces Masthead's real render pipeline:

- `manifest.json` parsing + validation (identical rules to upload)
- the **Solid/Liquid sandbox** with the same custom filters
  (`asset_url`, `strftime`, `iso8601`, `where_tag`, `search`)
- token → `:root { --… }` **CSS injection** (file tokens wrapped in
  `url(…)`, empty file tokens skipped, `object`/`list` tokens skipped)
- the **content pipeline** (Earmark markdown + the same HTML sanitizer),
  including Liquid bodies for `html`-format pages and posts
- **theme pages** (`templates/pages/<name>.liquid`) and their per-page
  settings, merged against the sidecar `<name>.json` schema
- the exact route table and controller logic of the public site

The renderer, presenter, manifest, sandbox, filters, CSS sanitizer and
content scrubber are faithful copies of the host application's modules, so a
template that previews correctly here renders the same way in production.

## Install

### Homebrew (recommended)

```sh
brew install dijkstrasoftware/tap/masthead
```

To track the latest `main` instead of the newest release:

```sh
brew install --HEAD dijkstrasoftware/tap/masthead
```

The formula lives in the
[dijkstrasoftware/homebrew-tap](https://github.com/dijkstrasoftware/homebrew-tap)
repository.

### From source

Requires Elixir (`~> 1.15`; developed on 1.18 / OTP 28).

```sh
git clone https://github.com/dijkstrasoftware/masthead-cli ~/personal/masthead_cli
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
masthead new my-theme            # scaffold a new theme from the template

cd my-theme
masthead preview                 # serves http://localhost:4010
masthead preview --port 4020     # pick a port
masthead preview --dir ../other  # point elsewhere
masthead preview --no-editor     # serve the theme bare, no sidebar

masthead validate                # check manifest + templates, no server
masthead package                 # zip the theme to ~/Desktop
masthead doctor                  # report Erlang/Elixir versions, flag mismatches
masthead help
```

## The preview editor

`masthead preview` opens an editor shell at `http://localhost:4010`: the theme
renders in an iframe, with the settings sidebar next to it. Any theme URL you
open lands there, and clicking through your theme's own navigation moves the
sidebar with you.

The sidebar has three parts:

- **Page** — jump to any page or post in your preview content.
- **Theme tokens** — every token in `manifest.json`, grouped by `category`.
- **Page settings** — the settings of the page currently in the frame: its
  sidecar config (`templates/pages/<name>.json`) for a theme page, otherwise
  the manifest's global `metadata`. The post list and post pages have none,
  same as in production.

Editing a field **re-renders the page on the server**. That matters: a `list`
token your template loops over, or a `boolean` your template branches on,
produces exactly the HTML the platform would produce — not a CSS-variable
approximation.

Everything else reloads by itself too: save a `.liquid` file, `theme.css` or
`manifest.json` and the frame refreshes.

### Where your edits go

Every value the sidebar writes goes into **`preview.local.json`** in the theme
directory:

```json
{
  "tokens": {
    "accent": "#d9480f",
    "footer": { "tagline": "Made in Utrecht" },
    "footer_links": [{ "label": "Docs", "url": "/docs" }]
  },
  "pages": {
    "home": { "metadata": { "hero": { "heading": "Hello" } } }
  }
}
```

This is a **preview-only scratchpad**. Nothing here is applied, uploaded, or
visible to the platform — it exists so your edits survive a refresh. It layers
on top of the `preview.json` seed you hand-author (which is never rewritten),
`masthead package` leaves it out of the zip, and `masthead preview` adds it to
your `.gitignore` for you. **Reset** in the sidebar throws it all away.

## Field types

A manifest `token`, a global `metadata` field and a theme page's sidecar field
are all the same declaration, with the same types:

| Type | Control |
| --- | --- |
| `color` | colour picker + hex field |
| `string`, `length`, `number`, `url` | text input |
| `text` | textarea |
| `select` | dropdown over `options` (required) |
| `boolean` | checkbox — reaches templates as a real boolean |
| `file` | asset picker (see below) |
| `object` | a group of nested scalar fields under one key |
| `list` | a repeatable group: add, reorder (drag), remove |

`object` and `list` nest one level deep — their `fields` must be scalars. A
`list` can declare `default` items and an `item_label` (the "Add …" button).

```json
{
  "key": "footer_links",
  "label": "Footer links",
  "type": "list",
  "item_label": "Link",
  "default": [],
  "fields": [
    { "key": "label", "label": "Label", "type": "string", "default": "" },
    { "key": "url", "label": "URL", "type": "url", "default": "" }
  ]
}
```

```liquid
{% for link in theme.tokens.footer_links %}
  <a href="{{ link.url }}">{{ link.label | escape }}</a>
{% endfor %}
```

Scalar tokens also become CSS custom properties (`--accent`); `object` and
`list` tokens are template-only and never reach the `:root` block.

## Creating a theme

`masthead new NAME` scaffolds a theme in a `NAME/` directory by cloning the
[theme template](https://github.com/dijkstrasoftware/masthead-template) — a
complete, valid starter with a theme page and example `object`/`list` tokens.
The template's git history is removed so you start clean, and the manifest's
`name`/`slug` are set from `NAME`:

```sh
masthead new my-theme
cd my-theme
masthead preview
```

The directory name seeds the slug (lowercased, hyphenated), so
`masthead new "My Theme"` produces slug `my-theme` and name `My Theme`. It
requires `git` on your PATH and won't overwrite a non-empty directory.

## Theme layout

```
manifest.json
theme.css
templates/
  layout.liquid      index.liquid     post.liquid
  page.liquid        not_found.liquid
  pages/             (optional — theme pages: <name>.liquid + <name>.json)
assets/              (optional — images, fonts, extra css)
preview.json         (optional — your preview content; not packaged)
preview.local.json   (written by the editor; gitignored, not packaged)
```

Files under `assets/` are served at `/assets/...`, matching
`{{ 'logo.png' | asset_url: theme.asset_base }}`.

## Packaging

`masthead package` bundles the theme into an installable Masthead theme zip —
exactly the files the platform consumes, and nothing else:

```
manifest.json
theme.css
templates/{layout,index,post,page,not_found}.liquid
templates/pages/*.liquid + *.json   (theme pages + their settings)
assets/…            (only whitelisted file types, no symlinks)
```

Dev-only files (`preview/`, `preview.json`, `preview.local.json`, `README.md`,
`.git`, `.DS_Store`, stray `*.zip`, …) are left out. The theme is validated
first (manifest + all templates + page configs must parse), so a broken theme
won't package, and the platform's upload limits (5 MB zip, 25 MB unpacked, 200
files) plus the reserved-slug / asset-type rules are checked up front and
reported as warnings.

```sh
masthead package                     # -> ~/Desktop/<slug>-<version>.zip
masthead package --out ~/Downloads   # into a directory
masthead package -o ./dist/theme.zip # exact file path
masthead package --bump minor        # bump manifest version first
```

## Preview content

With no configuration, the preview ships realistic sample content (a few
posts, an About page and a Blog page) so every theme has something to render.
Customise it with a `preview.json` in the theme directory:

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
  "tokens": { "accent": "#d9480f" },
  "pages": [
    { "title": "Home", "slug": "home", "format": "theme", "template": "home" }
  ],
  "posts": [
    { "title": "Hello", "slug": "hello", "published_at": "2026-01-15",
      "tags": ["Writing"], "body": "A post body." }
  ]
}
```

- `site.homepage` is the **slug** of the page served at `/` (just like setting
  a homepage in the Masthead admin). Omit it to render the `index` template.
- `tokens` seed the token values; the sidebar's edits layer on top.
- `pages` with `"format": "theme"` pick a `templates/pages/<template>.liquid`.
- A post's `tags` drive `tags`, `?tag=` filtering, `posts_by_tag` and the
  `where_tag` filter, exactly as on the live site.

### Posts and pages as Markdown files

Drop one file per post/page into `preview/posts/` and `preview/pages/`, with
an optional JSON **front matter** block:

```markdown
---
{ "title": "About", "slug": "about", "format": "markdown",
  "metadata": { "layout": "wide" }, "show_in_nav": true }
---
## About us

Markdown body goes here.
```

Anything omitted is inferred from the filename (`about.md` → slug `about`,
title `About`). `published_at` accepts an ISO-8601 datetime or a date. Posts
are ordered newest-first, pages by title — matching the live site's queries.
These files take precedence over inline `posts` / `pages` arrays in
`preview.json`.

## Variables available to templates

Same contract as production:

| Variable | Shape |
| --- | --- |
| `site` | `name`, `title`, `description`, `slug`, `css_overrides`, `homepage_slug` |
| `theme` | `name`, `slug`, `version`, `asset_base`, `tokens.<key>`, `css` |
| `post` | `title`, `slug`, `excerpt`, `published_at`, `url`, `tags` |
| `posts` | list of the above |
| `page` | `title`, `slug`, `format`, `template`, `url`, `metadata.<key>` |
| `pages` | list of the above (nav: homepage + `show_in_nav:false` excluded) |
| `tags` / `current_tag` | the site's tags (with `active`) and the one being filtered on |
| `posts_by_tag` | `posts_by_tag["slug"]` → the posts carrying that tag |
| `search_query` / `search_count` | on `/search` only |
| `body_html` | rendered post/page body (emit raw, do not `escape`) |
| `content` | (layout only) the rendered inner template |

Solid does **not** auto-escape — call `| escape` on user strings, exactly as
in production.

### Differences from production (by design)

- **File fields**: production stores an upload *id* and resolves it to a URL
  via the uploads table. There are no uploads locally, so a `file` value is
  used verbatim as a URL/path — the sidebar offers a picker over your theme's
  `assets/` folder, plus a free-text field for any URL. Empty file tokens emit
  no CSS declaration, just like production.
- **The editor injects a small script** into the theme's HTML (to keep the
  frame and the sidebar in sync). Production never touches theme output. Run
  `masthead preview --no-editor` to see the theme exactly as it ships.

## Development

```sh
mix test                      # renderer, manifest, packager, settings, router
mix format
mix compile --warnings-as-errors
```
