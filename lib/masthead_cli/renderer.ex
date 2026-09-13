defmodule MastheadCli.Renderer do
  @moduledoc """
  Top-level theme render API — faithful copy of `Masthead.Themes.Renderer`.

  The server hands in a loaded theme (manifest + parsed templates + css) and a
  plain map of assigns, and gets back a rendered body. This module picks the
  renderer the theme's manifest pins itself to via `render_version`:

    * no `render_version` (or `"beta"`) — `MastheadCli.Renderer.Beta`
    * `"v1"` — `MastheadCli.Renderer.V1`

  Both are frozen copies, exactly as in the platform, so a theme previews the
  way the version it names renders in production.
  """

  alias MastheadCli.Renderer.{Beta, V1}

  @doc "Render the site homepage (post list)."
  def render_index(theme, assigns), do: dispatch(theme, :render_index, assigns)

  @doc "Render a single blog post."
  def render_post(theme, assigns), do: dispatch(theme, :render_post, assigns)

  @doc "Render a standalone page (markdown or html)."
  def render_page(theme, assigns), do: dispatch(theme, :render_page, assigns)

  @doc "Render a theme page (`templates/pages/<template>.liquid`)."
  def render_theme_page(theme, assigns), do: dispatch(theme, :render_theme_page, assigns)

  @doc "Render the site-scoped 404."
  def render_not_found(theme, assigns), do: dispatch(theme, :render_not_found, assigns)

  @doc "Render search results."
  def render_search(theme, assigns), do: dispatch(theme, :render_search, assigns)

  @doc """
  The renderer module a theme's manifest pins itself to. The sidebar shows this
  so a theme author can see which contract they are previewing against.
  """
  def module_for("v1"), do: V1
  def module_for(_render_version), do: Beta

  defp dispatch(theme, fun, assigns) do
    apply(module_for(theme.manifest.render_version), fun, [theme, assigns])
  end
end
