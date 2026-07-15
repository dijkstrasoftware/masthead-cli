defmodule MastheadCli.Preview.State do
  @moduledoc """
  The JSON payload the settings sidebar is built from: the theme's token schema
  and the schema of whatever page the iframe is currently showing, each with
  their current values, plus the routes and assets the sidebar offers to pick.

  Schemas come straight from the manifest (`tokens`) and the page's sidecar
  config (`templates/pages/<name>.json`), so what the sidebar renders is exactly
  what the platform's own settings form would render for the same theme.
  """

  alias MastheadCli.Manifest
  alias MastheadCli.Preview.Settings

  @doc """
  Build the sidebar state for the page at `path` (the iframe's current URL).
  """
  def build(theme, data, dir, path) do
    manifest = theme.manifest
    tokens = Map.get(data.site, :theme_tokens) || %{}

    %{
      theme: %{name: manifest.name, slug: manifest.slug, version: manifest.version},
      tokens: %{
        fields: manifest.tokens,
        values: Manifest.effective_tokens(manifest, tokens)
      },
      page: page_state(theme, data, path),
      routes: routes(data),
      assets: assets(dir),
      settings_file: Settings.filename()
    }
  end

  # ---- the page currently in the frame ----

  # Index, post and search routes have no page settings — production doesn't
  # expose `page` there either, so there is nothing to edit.
  defp page_state(theme, data, path) do
    case resolve_page(data, path) do
      nil ->
        nil

      page ->
        fields = fields_for(theme, page)

        %{
          slug: page.slug,
          title: page.title,
          format: page.format,
          template: Map.get(page, :template),
          label: page_label(theme, page),
          description: page_description(theme, page),
          fields: fields,
          values: Manifest.merge_fields(fields, page.metadata || %{})
        }
    end
  end

  # A theme page's settings come from its sidecar config; a markdown/html page
  # uses the theme's global `metadata` schema.
  defp fields_for(theme, %{format: "theme", template: template}) when is_binary(template) do
    case Map.get(theme.page_configs, template) do
      %{metadata: fields} when is_list(fields) -> fields
      _ -> []
    end
  end

  defp fields_for(theme, _page), do: theme.manifest.metadata

  defp page_label(theme, %{format: "theme", template: template} = page)
       when is_binary(template) do
    case Map.get(theme.page_configs, template) do
      %{label: label} when is_binary(label) -> label
      _ -> page.title
    end
  end

  defp page_label(_theme, page), do: page.title

  defp page_description(theme, %{format: "theme", template: template})
       when is_binary(template) do
    case Map.get(theme.page_configs, template) do
      %{description: description} -> description
      _ -> nil
    end
  end

  defp page_description(_theme, _page), do: nil

  @doc """
  The page a preview path renders, or nil for the post list / a post / search.
  `/` is the site's designated homepage page when it has one.
  """
  def resolve_page(data, path) do
    case String.split(String.trim(path, "/"), "/") do
      [""] -> homepage(data)
      ["posts", _slug] -> nil
      ["search"] -> nil
      [slug] -> Enum.find(data.pages, &(&1.slug == slug))
      _ -> nil
    end
  end

  defp homepage(%{site: site, pages: pages}) do
    case Map.get(site, :homepage_slug) do
      slug when is_binary(slug) -> Enum.find(pages, &(&1.slug == slug))
      _ -> nil
    end
  end

  # ---- the route picker ----

  defp routes(%{site: site, pages: pages, posts: posts}) do
    home = Map.get(site, :homepage_slug)

    index = %{label: "Home", path: "/", kind: "index"}

    page_routes =
      Enum.map(pages, fn page ->
        %{
          label: page.title,
          path: if(page.slug == home, do: "/", else: "/" <> page.slug),
          kind: if(page.format == "theme", do: "theme page", else: page.format)
        }
      end)

    post_routes =
      Enum.map(posts, fn post ->
        %{label: post.title, path: "/posts/" <> post.slug, kind: "post"}
      end)

    Enum.uniq_by([index] ++ page_routes ++ post_routes, & &1.path)
  end

  # ---- the asset picker ----

  # Every file under the theme's assets/, as the URL the preview serves it at —
  # the values a `file` field takes here (production stores an upload id; the
  # preview has no uploads, so a path or URL is used verbatim).
  defp assets(dir) do
    root = Path.join(dir, "assets")

    root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&("/assets/" <> Path.relative_to(&1, root)))
    |> Enum.sort()
  end
end
