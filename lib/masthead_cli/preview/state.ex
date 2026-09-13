defmodule MastheadCli.Preview.State do
  @moduledoc """
  The JSON payload the settings sidebar is built from: the theme's token schema
  and the schema of whatever the iframe is currently showing, each with their
  current values, plus the routes and assets the sidebar offers to pick.

  The per-route schema (`settings`) is a page's or a post's, tagged with `kind`
  so the sidebar knows which it is editing and the server knows where to store
  it. Schemas come straight from the manifest (`tokens`, `page_options`,
  `post_options`) and a theme page's sidecar config
  (`templates/pages/<name>.json`), so what the sidebar renders is exactly what
  the platform's own settings form would render for the same theme.
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
      theme: %{
        name: manifest.name,
        slug: manifest.slug,
        version: manifest.version,
        render_version: manifest.render_version
      },
      tokens: %{
        fields: manifest.tokens,
        values: Manifest.effective_tokens(manifest, tokens)
      },
      settings: settings_state(theme, data, path),
      content: content_state(theme, data),
      routes: routes(data),
      assets: assets(dir),
      settings_file: Settings.filename()
    }
  end

  # ---- the preview content, in the shape the sidebar edits it ----

  # Whatever is showing now — built-in samples, preview.json, or the sidebar's
  # own edits — projected back into the same JSON vocabulary `preview.json`
  # uses, so editing it in the sidebar and hand-writing it stay interchangeable.
  # Each item carries its own effective options, and the schemas travel with the
  # list, so the sidebar can edit any post's or page's options — not only those
  # of whatever happens to be in the frame.
  defp content_state(theme, data) do
    %{
      posts: Enum.map(data.posts, &post_item(theme, &1)),
      pages: Enum.map(data.pages, &page_item(theme, &1)),
      templates: theme.page_templates |> Map.keys() |> Enum.sort(),
      post_fields: theme.manifest.post_options,
      page_fields: theme.manifest.page_options,
      page_configs: page_config_fields(theme)
    }
  end

  defp post_item(theme, post) do
    fields = theme.manifest.post_options

    %{
      "title" => post.title,
      "slug" => post.slug,
      "excerpt" => Map.get(post, :excerpt) || "",
      "format" => Map.get(post, :format) || "markdown",
      "published_at" => published_on(Map.get(post, :published_at)),
      "tags" => Enum.map(Map.get(post, :tags) || [], & &1.name),
      "body" => Map.get(post, :body) || "",
      "options" => Manifest.merge_fields(fields, Map.get(post, :post_options) || %{})
    }
  end

  defp page_item(theme, page) do
    fields = page_fields(theme, page)

    %{
      "title" => page.title,
      "slug" => page.slug,
      "format" => Map.get(page, :format) || "markdown",
      "template" => Map.get(page, :template),
      "show_in_nav" => Map.get(page, :show_in_nav, true),
      "body" => Map.get(page, :body) || "",
      "options" => Manifest.merge_fields(fields, Map.get(page, :page_options) || %{})
    }
  end

  # Every theme page's sidecar schema, keyed by template name, so the sidebar
  # can pick the right one when a page's template changes under its hands.
  defp page_config_fields(theme) do
    Map.new(theme.page_configs, fn {name, config} ->
      {name,
       %{
         label: Map.get(config, :label),
         description: Map.get(config, :description),
         fields: Map.get(config, :page_options) || []
       }}
    end)
  end

  # A date is what the editor offers; the seed accepts a full ISO-8601 stamp
  # too, so only the date part round-trips through the sidebar.
  defp published_on(%DateTime{} = at), do: at |> DateTime.to_date() |> Date.to_iso8601()
  defp published_on(_), do: nil

  # ---- what the frame is currently showing ----

  # The index and search routes have no per-route settings — production doesn't
  # expose a page or a post there either, so there is nothing to edit.
  defp settings_state(theme, data, path) do
    case resolve_target(data, path) do
      {:page, page} -> page_settings(theme, page)
      {:post, post} -> post_settings(theme, post)
      nil -> nil
    end
  end

  defp page_settings(theme, page) do
    fields = page_fields(theme, page)

    %{
      kind: "page",
      slug: page.slug,
      title: page.title,
      format: page.format,
      template: Map.get(page, :template),
      label: page_label(theme, page),
      description: page_description(theme, page),
      fields: fields,
      values: Manifest.merge_fields(fields, Map.get(page, :page_options) || %{})
    }
  end

  defp post_settings(theme, post) do
    fields = theme.manifest.post_options

    %{
      kind: "post",
      slug: post.slug,
      title: post.title,
      format: post.format,
      template: nil,
      label: post.title,
      description: nil,
      fields: fields,
      values: Manifest.merge_fields(fields, Map.get(post, :post_options) || %{})
    }
  end

  @doc """
  The option fields a page is edited with: a theme page's come from its sidecar
  config, a markdown/html page's from the theme's global `page_options`.
  """
  def page_fields(theme, %{format: "theme", template: template}) when is_binary(template) do
    case Map.get(theme.page_configs, template) do
      %{page_options: fields} when is_list(fields) -> fields
      _ -> []
    end
  end

  def page_fields(theme, _page), do: theme.manifest.page_options

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
  What a preview path renders: `{:page, page}`, `{:post, post}`, or nil for the
  post list and search. `/` is the site's designated homepage page when it has
  one.
  """
  def resolve_target(data, path) do
    case String.split(String.trim(path, "/"), "/") do
      [""] -> wrap(:page, homepage(data))
      ["posts", slug] -> wrap(:post, Enum.find(data.posts, &(&1.slug == slug)))
      ["search"] -> nil
      [slug] -> wrap(:page, Enum.find(data.pages, &(&1.slug == slug)))
      _ -> nil
    end
  end

  defp wrap(_kind, nil), do: nil
  defp wrap(kind, item), do: {kind, item}

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
