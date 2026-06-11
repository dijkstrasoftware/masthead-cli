defmodule MastheadCli.Presenter do
  @moduledoc """
  Project preview fixtures into the plain string-keyed maps that themes
  see, matching `Masthead.Themes.Presenter` exactly.

  The host application projects Ecto schemas here; the CLI projects the
  plain maps produced by `MastheadCli.PreviewConfig`. The *output* shapes
  are identical, so a template that works in preview works in production.

  Fixture inputs are atom-keyed maps:

    * site: `%{name, title, description, slug, css_overrides, homepage_slug, theme_tokens}`
    * post: `%{title, slug, excerpt, published_at, body, format}`
    * page: `%{title, slug, format, body, metadata, show_in_nav}`
  """

  alias MastheadCli.CssSanitizer

  @doc "Project a site, including the per-site CSS overrides string."
  def site(s) do
    %{
      "name" => s.name,
      "title" => s.title,
      "description" => s.description,
      "slug" => s.slug,
      "css_overrides" => CssSanitizer.sanitize_overrides(Map.get(s, :css_overrides)),
      "homepage_slug" => Map.get(s, :homepage_slug)
    }
  end

  def post(p) do
    %{
      "title" => p.title,
      "slug" => p.slug,
      "excerpt" => Map.get(p, :excerpt, ""),
      "published_at" => Map.get(p, :published_at),
      "url" => "/posts/" <> p.slug
    }
  end

  def page(pg) do
    %{
      "title" => pg.title,
      "slug" => pg.slug,
      "format" => pg.format,
      "url" => "/" <> pg.slug,
      # Raw override map. The Renderer merges manifest defaults on top of
      # this before exposing it to templates.
      "metadata" => Map.get(pg, :metadata) || %{}
    }
  end

  @doc "Convenience: project a list of posts."
  def posts(list) when is_list(list), do: Enum.map(list, &post/1)

  @doc "Convenience: project a list of pages."
  def pages(list) when is_list(list), do: Enum.map(list, &page/1)
end
