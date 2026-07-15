defmodule MastheadCli.Filters do
  @moduledoc """
  Custom Liquid filters made available to every theme. Faithful copy of
  `Masthead.Themes.Filters`. Solid's `Solid.StandardFilter` set
  (`escape`, `default`, `date`, `size`, ...) is always loaded first;
  anything here takes precedence on name collision.
  """

  @doc """
  Build an asset URL given a theme's storage base and a relative file
  name:

      {{ 'logo.png' | asset_url: theme.asset_base }}

  In the CLI preview `theme.asset_base` is `/assets`, so this resolves to
  `/assets/logo.png`, served straight from the theme's `assets/` folder.
  Falls back to the bare filename if the base is missing.
  """
  def asset_url(filename, base) when is_binary(filename) and is_binary(base) do
    base
    |> String.trim_trailing("/")
    |> Kernel.<>("/")
    |> Kernel.<>(String.trim_leading(filename, "/"))
  end

  def asset_url(filename, _), do: filename

  @doc """
  Format a `DateTime` (or anything with `to_iso8601/1`) using
  `Calendar.strftime/2`.

      {{ post.published_at | strftime: "%B %-d, %Y" }}
  """
  def strftime(%DateTime{} = dt, format) when is_binary(format) do
    Calendar.strftime(dt, format)
  end

  def strftime(%NaiveDateTime{} = dt, format) when is_binary(format) do
    Calendar.strftime(dt, format)
  end

  def strftime(%Date{} = d, format) when is_binary(format) do
    Calendar.strftime(d, format)
  end

  def strftime(nil, _format), do: ""
  def strftime(other, _format), do: to_string(other)

  @doc """
  ISO-8601 string for use in `<time datetime="...">`. Defensive against
  nils so templates can do `{{ post.published_at | iso8601 }}`
  unconditionally.
  """
  def iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def iso8601(%Date{} = d), do: Date.to_iso8601(d)
  def iso8601(nil), do: ""
  def iso8601(other), do: to_string(other)

  @doc """
  Keep only the posts carrying the tag with the given slug, so a theme can use
  tagged posts as generic content blocks:

      {% assign faqs = posts | where_tag: "faq" %}

  Non-list input (or a missing slug) yields an empty list.
  """
  def where_tag(posts, slug) when is_list(posts) and is_binary(slug) do
    Enum.filter(posts, fn post ->
      post
      |> tags_list()
      |> Enum.any?(fn tag -> Map.get(tag, "slug") == slug end)
    end)
  end

  def where_tag(_posts, _slug), do: []

  @doc """
  Filter posts by a case-insensitive substring match on their title or excerpt:

      {% assign hits = posts | search: search_query %}

  A blank query returns the list unchanged.
  """
  def search(posts, query) when is_list(posts) and is_binary(query) do
    case String.trim(query) do
      "" ->
        posts

      trimmed ->
        needle = String.downcase(trimmed)

        Enum.filter(posts, fn post ->
          contains?(Map.get(post, "title"), needle) or
            contains?(Map.get(post, "excerpt"), needle)
        end)
    end
  end

  def search(posts, _query) when is_list(posts), do: posts
  def search(_posts, _query), do: []

  defp tags_list(post) do
    case Map.get(post, "tags") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp contains?(value, needle) when is_binary(value),
    do: String.contains?(String.downcase(value), needle)

  defp contains?(_value, _needle), do: false
end
