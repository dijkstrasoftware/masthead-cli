defmodule MastheadCli do
  @moduledoc """
  `masthead_cli` — a standalone preview server for [Masthead](https://masthead.site)
  themes.

  It reproduces the host platform's theme render pipeline (manifest parsing,
  the Solid/Liquid sandbox, custom filters, token → `:root` CSS injection,
  the content pipeline, and the per-page metadata merge) so a theme author
  can run `masthead preview` inside a theme directory and see exactly how
  the theme will render in production — no database, no Phoenix app.

  See `MastheadCli.CLI` for the command-line surface.
  """
end
