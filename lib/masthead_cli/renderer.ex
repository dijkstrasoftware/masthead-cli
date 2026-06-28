defmodule MastheadCli.Renderer do
  @moduledoc """
  Top-level theme render API — faithful copy of `Masthead.Themes.Renderer`,
  with the two production-only dependencies stubbed out for local preview:

    * Theme resolution: the production renderer looks the theme up by
      `site.theme_id`; here the loaded theme (manifest + parsed templates +
      css) is passed in directly by the server.
    * File-token resolution: production maps a stored upload **id** to a
      public URL via the uploads table. There are no uploads in preview, so
      a `file` token's value is used verbatim as a URL/path. A blank value
      emits no CSS declaration, exactly as in production.

  Everything else — token merging, the appended `:root {}` cascade, the
  layout wrap, the sandbox — is identical to production.
  """

  alias MastheadCli.{CssSanitizer, Manifest, Presenter, Sandbox}

  @doc "Render the site homepage (post list)."
  def render_index(theme, %{site: site, posts: posts, pages: pages}) do
    render(theme, site, :index, %{
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "post" => nil,
      "page" => nil,
      "body_html" => ""
    })
  end

  @doc "Render a single blog post."
  def render_post(theme, %{site: site, post: post, body_html: body_html, pages: pages}) do
    render(theme, site, :post, %{
      "post" => Presenter.post(post),
      "pages" => Presenter.pages(pages),
      "posts" => [],
      "page" => nil,
      "body_html" => body_html
    })
  end

  @doc "Render a standalone page (markdown or html)."
  def render_page(theme, %{site: site, page: page, body_html: body_html, pages: pages}) do
    render(theme, site, :page, %{
      "page" => Presenter.page(page),
      "pages" => Presenter.pages(pages),
      "posts" => [],
      "post" => nil,
      "body_html" => body_html
    })
  end

  @doc """
  Render a theme page: a `templates/pages/<template>.liquid` page. It gets the
  full post list (so e.g. a blog page can list posts) and its settings come from
  the page's sidecar config; theme pages have no editable body.
  """
  def render_theme_page(theme, %{site: site, page: page, posts: posts, pages: pages}) do
    render(theme, site, {:page_template, page.template}, %{
      "page" => Presenter.page(page),
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "post" => nil,
      "body_html" => ""
    })
  end

  @doc "Render the site-scoped 404."
  def render_not_found(theme, %{site: site, pages: pages}) do
    render(theme, site, :not_found, %{
      "pages" => Presenter.pages(pages),
      "posts" => [],
      "post" => nil,
      "page" => nil,
      "body_html" => ""
    })
  end

  # ---- core ----

  defp render(theme, site, target, target_assigns) do
    manifest = theme.manifest
    file_keys = file_token_keys(manifest)

    tokens = Manifest.effective_tokens(manifest, Map.get(site, :theme_tokens) || %{})

    base_context = %{
      "site" => Presenter.site(site),
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

    {:ok, inner_iodata, _errs} = Sandbox.render(inner_template, inner_context)
    inner_html = IO.iodata_to_binary(inner_iodata)

    layout_context = Map.put(inner_context, "content", inner_html)
    {:ok, layout_iodata, _errs} = Sandbox.render(layout_template, layout_context)

    IO.iodata_to_binary(layout_iodata)
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
      |> Enum.map_join(" ", fn {k, v} -> declaration(k, v, file_keys) end)
      |> String.trim()

    theme_css <> "\n:root { " <> declarations <> " }\n"
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
