defmodule MastheadCli.Renderer do
  @moduledoc """
  Top-level theme render API — faithful copy of `Masthead.Themes.Renderer`,
  with the two production-only dependencies stubbed out for local preview:

    * Theme resolution: the production renderer looks the theme up by
      `site.theme_id`; here the loaded theme (manifest + parsed templates +
      css) is passed in directly by the server.
    * File-field resolution: production maps a stored upload **id** to a
      public URL via the uploads table. There are no uploads in preview, so a
      `file` value (a token, a page-metadata field, or one nested inside an
      `object`/`list`) is used verbatim as a URL/path. A blank value emits no
      CSS declaration, exactly as in production.

  Everything else — token merging (including `object`/`list` containers), the
  appended `:root {}` cascade, the layout wrap, the sandbox — is identical to
  production.
  """

  alias MastheadCli.{CssSanitizer, Manifest, Presenter, Sandbox}

  @doc "Render the site homepage (post list)."
  def render_index(theme, %{site: site, posts: posts, pages: pages} = assigns) do
    current_tag = Map.get(assigns, :current_tag)

    render(theme, site, :index, assigns, %{
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "tags" => Presenter.tags(Map.get(assigns, :tags, []), current_tag && current_tag.slug),
      "current_tag" => Presenter.tag(current_tag),
      "post" => nil,
      "page" => nil,
      "body_html" => ""
    })
  end

  @doc "Render a single blog post."
  def render_post(theme, %{site: site, post: post, pages: pages} = assigns) do
    render(theme, site, :post, assigns, %{
      "post" => Presenter.post(post),
      "pages" => Presenter.pages(pages),
      "posts" => Presenter.posts(Map.get(assigns, :posts, [])),
      "page" => nil,
      "body_html" => Map.get(assigns, :body_html, "")
    })
  end

  @doc "Render a standalone page (markdown or html)."
  def render_page(theme, %{site: site, page: page, pages: pages} = assigns) do
    render(theme, site, :page, assigns, %{
      "page" => Presenter.page(page),
      "pages" => Presenter.pages(pages),
      "posts" => Presenter.posts(Map.get(assigns, :posts, [])),
      "post" => nil,
      "body_html" => Map.get(assigns, :body_html, "")
    })
  end

  @doc """
  Render a theme page: a `templates/pages/<template>.liquid` page. It gets the
  full post list (so e.g. a blog page can list posts) and its settings come from
  the page's sidecar config; theme pages have no editable body.
  """
  def render_theme_page(theme, %{site: site, page: page, posts: posts, pages: pages} = assigns) do
    current_tag = Map.get(assigns, :current_tag)

    render(theme, site, {:page_template, page.template}, assigns, %{
      "page" => Presenter.page(page),
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "tags" => Presenter.tags(Map.get(assigns, :tags, []), current_tag && current_tag.slug),
      "current_tag" => Presenter.tag(current_tag),
      "post" => nil,
      "body_html" => ""
    })
  end

  @doc "Render the site-scoped 404."
  def render_not_found(theme, %{site: site, pages: pages} = assigns) do
    render(theme, site, :not_found, assigns, %{
      "pages" => Presenter.pages(pages),
      "posts" => Presenter.posts(Map.get(assigns, :posts, [])),
      "post" => nil,
      "page" => nil,
      "body_html" => ""
    })
  end

  @doc """
  Render the search results page. Reuses the `index` template, with
  `search_query` / `search_count` in the context (a blank query normalises to
  `nil`, because an empty string is truthy in Liquid).
  """
  def render_search(theme, %{site: site, posts: posts, pages: pages, query: query} = assigns) do
    search_query = if is_binary(query) and String.trim(query) != "", do: query, else: nil

    render(theme, site, :index, assigns, %{
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "tags" => [],
      "current_tag" => nil,
      "post" => nil,
      "page" => nil,
      "body_html" => "",
      "search_query" => search_query,
      "search_count" => length(posts)
    })
  end

  # ---- core ----

  defp render(theme, site, target, assigns, target_assigns) do
    manifest = theme.manifest
    file_keys = file_token_keys(manifest)

    tokens = Manifest.effective_tokens(manifest, Map.get(site, :theme_tokens) || %{})

    base_context = %{
      "site" => Presenter.site(site),
      "posts_by_tag" => posts_by_tag(assigns),
      "theme" => %{
        "name" => manifest.name,
        "slug" => manifest.slug,
        "version" => manifest.version,
        "asset_base" => theme.asset_base,
        "tokens" => tokens,
        "css" => composed_css(theme.css, tokens, file_keys)
      }
    }

    inner_template = fetch_template!(theme, target)
    layout_template = Map.fetch!(theme.templates, :layout)

    inner_context =
      base_context
      |> Map.merge(target_assigns)
      |> compose_page_metadata(theme)
      |> render_liquid_body(Map.get(assigns, :liquid_body))

    {:ok, inner_iodata, _errs} = Sandbox.render(inner_template, inner_context)
    inner_html = IO.iodata_to_binary(inner_iodata)

    layout_context = Map.put(inner_context, "content", inner_html)
    {:ok, layout_iodata, _errs} = Sandbox.render(layout_template, layout_context)

    IO.iodata_to_binary(layout_iodata)
  end

  # Production resolves `posts_by_tag["slug"]` with a per-tag DB query. The
  # preview dataset is already in memory, so the same lookup is a plain map —
  # Solid's map access behaves identically. Built from the *unfiltered* post
  # list, so a tag block on a `?tag=`-filtered page still sees every post.
  defp posts_by_tag(assigns) do
    assigns
    |> Map.get(:all_posts, Map.get(assigns, :posts, []))
    |> Presenter.posts()
    |> Enum.reduce(%{}, fn post, acc ->
      Enum.reduce(post["tags"] || [], acc, fn tag, inner ->
        Map.update(inner, tag["slug"], [post], &(&1 ++ [post]))
      end)
    end)
  end

  # Pick the inner template: a plain atom is a fixed template; a
  # `{:page_template, name}` is a theme page from `templates/pages/`. A missing
  # page template falls back to the legacy `:blog` (for that name) or the
  # generic `:page` so the page still renders.
  defp fetch_template!(theme, target) when is_atom(target),
    do: Map.fetch!(theme.templates, target)

  defp fetch_template!(theme, {:page_template, name}) do
    cond do
      is_binary(name) and Map.has_key?(theme.page_templates, name) -> theme.page_templates[name]
      name == "blog" and Map.has_key?(theme.templates, :blog) -> theme.templates[:blog]
      true -> Map.fetch!(theme.templates, :page)
    end
  end

  # A theme page resolves its overrides against its sidecar config's field
  # schema; every other page uses the theme's global `metadata` schema. In the
  # CLI there are no uploads, so `file` values are used verbatim (no id→URL).
  defp compose_page_metadata(%{"page" => %{"template" => template} = page} = context, theme)
       when is_binary(template) and template != "" do
    apply_effective(context, page, page_config_fields(theme, template))
  end

  defp compose_page_metadata(%{"page" => %{} = page} = context, theme) do
    apply_effective(context, page, theme.manifest.metadata)
  end

  defp compose_page_metadata(context, _theme), do: context

  defp page_config_fields(theme, template) do
    case Map.get(theme.page_configs, template) do
      %{metadata: fields} when is_list(fields) -> fields
      _ -> []
    end
  end

  defp apply_effective(context, page, fields) do
    raw = Map.get(page, "metadata", %{})
    effective = Manifest.merge_fields(fields, raw)
    Map.put(context, "page", Map.put(page, "metadata", effective))
  end

  # An `html`-format post/page body is itself Liquid: render it against the same
  # context (so it can read `page.metadata.*`) and hand the result to the
  # template as `body_html`, unsanitized — matching production.
  defp render_liquid_body(context, raw_body) when is_binary(raw_body) do
    body_html =
      case Sandbox.render_string(raw_body, context) do
        {:ok, iodata} -> IO.iodata_to_binary(iodata)
        {:error, _err} -> raw_body
      end

    Map.put(context, "body_html", body_html)
  end

  defp render_liquid_body(context, _raw_body), do: context

  # The set of token keys declared as `file` in the manifest. These are
  # emitted as `url(...)` in the cascade.
  defp file_token_keys(%Manifest{tokens: tokens}) do
    for %{key: key, type: "file"} <- tokens, into: MapSet.new(), do: key
  end

  # Token overrides go AFTER the theme's CSS so they win in the cascade.
  defp composed_css(theme_css, tokens, _file_keys) when map_size(tokens) == 0, do: theme_css

  defp composed_css(theme_css, tokens, file_keys) do
    declarations =
      tokens
      # `object`/`list` tokens are template-only — a map or a list of maps has
      # no CSS custom-property form, so they never reach the `:root` block.
      |> Enum.reject(fn {_k, v} -> is_map(v) or is_list(v) end)
      |> Enum.map_join(" ", fn {k, v} -> declaration(k, v, file_keys) end)
      |> String.trim()

    if declarations == "" do
      theme_css
    else
      theme_css <> "\n:root { " <> declarations <> " }\n"
    end
  end

  # File tokens carry a URL — wrap as `url(...)`. Skip empty file tokens so
  # we never emit a useless `--key: url();`.
  defp declaration(key, value, file_keys) do
    if MapSet.member?(file_keys, key) do
      case CssSanitizer.sanitize_token_value(value) do
        "" -> ""
        url -> "--#{kebab(key)}: url(#{url});"
      end
    else
      "--#{kebab(key)}: #{CssSanitizer.sanitize_token_value(value)};"
    end
  end

  defp kebab(key), do: String.replace(key, "_", "-")
end
