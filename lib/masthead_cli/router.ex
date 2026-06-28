defmodule MastheadCli.Router do
  @moduledoc """
  The preview HTTP router — a plain Plug that reproduces the route table
  and controller logic of `MastheadWeb.PublicRouter` / `PublicController`:

      GET /              -> homepage page (if configured) else post-list index
      GET /posts/:slug   -> single post, or themed 404
      GET /:slug         -> single page (page/blog format), or themed 404
      GET /assets/*path  -> static files from the theme's assets/ folder

  The theme and the preview dataset are re-read on every request, so edits
  to templates, CSS, the manifest, or preview content appear on refresh.
  Theme load errors and template render errors are shown as an in-browser
  diagnostic page rather than crashing the connection.
  """

  @behaviour Plug
  import Plug.Conn

  alias MastheadCli.{Content, Inspector, PreviewConfig, Renderer, Term, Theme}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    dir = Keyword.fetch!(opts, :dir)
    inspector? = Keyword.get(opts, :inspector, true)
    conn = fetch_query_params(conn)

    response =
      case conn.path_info do
        [] -> render_request(dir, :index, nil, inspector?)
        ["posts", slug] -> render_request(dir, :post, slug, inspector?)
        ["assets" | rest] -> {:asset, rest}
        [slug] -> render_request(dir, :page, slug, inspector?)
        _ -> render_request(dir, :not_found, nil, inspector?)
      end

    send_response(conn, dir, response)
  end

  # ---- request handling (theme reloaded per request) ----

  defp render_request(dir, target, slug, inspector?) do
    case Theme.load(dir) do
      {:ok, theme} ->
        data = PreviewConfig.load(dir)

        try do
          theme
          |> dispatch(data, target, slug)
          |> maybe_inject(inspector?, theme, data)
        rescue
          e ->
            {:error_page, 500, "Render error", Exception.format(:error, e, __STACKTRACE__)}
        end

      {:error, reason} ->
        {:error_page, 500, "Theme failed to load", format_load_error(reason)}
    end
  end

  # The sketchy bit: splice the dev-only token inspector into a successfully
  # rendered themed page. Error pages and assets are left untouched.
  defp maybe_inject({:ok, status, body}, true, theme, %{site: site}) do
    tokens = Map.get(site, :theme_tokens) || %{}
    {:ok, status, Inspector.inject(body, theme.manifest, tokens)}
  end

  defp maybe_inject(response, _inspector?, _theme, _data), do: response

  defp dispatch(theme, %{site: site, posts: posts, pages: pages}, :index, _slug) do
    nav = nav_pages(site, pages)

    case homepage_page(site, pages) do
      nil ->
        {:ok, 200, Renderer.render_index(theme, %{site: site, posts: posts, pages: nav})}

      page ->
        render_page_target(theme, site, page, posts, nav)
    end
  end

  defp dispatch(theme, %{site: site, posts: posts, pages: pages}, :post, slug) do
    nav = nav_pages(site, pages)

    case Enum.find(posts, &(&1.slug == slug)) do
      nil ->
        {:ok, 404, Renderer.render_not_found(theme, %{site: site, pages: nav})}

      post ->
        body_html = Content.render_body(post.body, post.format)

        {:ok, 200,
         Renderer.render_post(theme, %{site: site, post: post, body_html: body_html, pages: nav})}
    end
  end

  defp dispatch(theme, %{site: site, posts: posts, pages: pages}, :page, slug) do
    nav = nav_pages(site, pages)

    case Enum.find(pages, &(&1.slug == slug)) do
      nil ->
        {:ok, 404, Renderer.render_not_found(theme, %{site: site, pages: nav})}

      page ->
        render_page_target(theme, site, page, posts, nav)
    end
  end

  defp dispatch(theme, %{site: site, pages: pages}, :not_found, _slug) do
    {:ok, 404, Renderer.render_not_found(theme, %{site: site, pages: nav_pages(site, pages)})}
  end

  # A theme page renders a templates/pages/<template>.liquid layout with the
  # full post list available; everything else renders as a plain page. Mirrors
  # PublicController.render_page_or_404/3.
  defp render_page_target(theme, site, %{format: "theme"} = page, posts, nav) do
    {:ok, 200,
     Renderer.render_theme_page(theme, %{
       site: site,
       page: page,
       posts: posts,
       pages: nav
     })}
  end

  defp render_page_target(theme, site, page, _posts, nav) do
    body_html = Content.render_body(page.body, page.format)

    {:ok, 200,
     Renderer.render_page(theme, %{site: site, page: page, body_html: body_html, pages: nav})}
  end

  # The nav excludes the designated homepage and any page hidden via
  # show_in_nav: false. Mirrors PublicController.nav_pages/2.
  defp nav_pages(site, pages) do
    home = Map.get(site, :homepage_slug)

    Enum.reject(pages, fn p ->
      p.slug == home or Map.get(p, :show_in_nav) == false
    end)
  end

  defp homepage_page(site, pages) do
    case Map.get(site, :homepage_slug) do
      nil -> nil
      slug -> Enum.find(pages, &(&1.slug == slug))
    end
  end

  # ---- responses ----

  defp send_response(conn, _dir, {:ok, status, body}) do
    log(conn, status)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
  end

  defp send_response(conn, _dir, {:error_page, status, title, detail}) do
    log(conn, status)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, error_page(title, detail))
  end

  defp send_response(conn, dir, {:asset, rest}) do
    safe = Enum.reject(rest, &(&1 in ["", ".", ".."]))
    path = Path.join([dir, "assets" | safe])

    if File.regular?(path) do
      log(conn, 200)

      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> send_file(200, path)
    else
      log(conn, 404)
      send_resp(conn, 404, "asset not found: #{Enum.join(safe, "/")}")
    end
  end

  defp log(conn, status) do
    path = "/" <> Enum.join(conn.path_info, "/")
    IO.puts("  #{Term.status(status)}  #{Term.dim(conn.method)} #{path}")
  end

  # ---- diagnostics ----

  defp format_load_error({:missing, message}), do: message

  defp format_load_error({:manifest, errors}) do
    "manifest.json is invalid:\n\n" <> Enum.map_join(errors, "\n", &("  • " <> &1))
  end

  defp format_load_error({:templates, errors}) do
    "Template problems:\n\n" <>
      Enum.map_join(errors, "\n\n", fn {name, msg} ->
        "  templates/#{name}.liquid:\n    #{msg}"
      end)
  end

  defp format_load_error(other), do: inspect(other)

  defp error_page(title, detail) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>#{escape(title)} — masthead preview</title>
      <style>
        :root { color-scheme: light dark; }
        body { margin: 0; font: 15px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace;
               background: #1a1a1a; color: #f5f5f5; padding: 2.5rem; }
        .wrap { max-width: 820px; margin: 0 auto; }
        h1 { font-size: 1.25rem; color: #ff6b6b; margin: 0 0 .25rem; }
        p.sub { color: #aaa; margin: 0 0 1.5rem; }
        pre { background: #0f0f0f; border: 1px solid #333; border-radius: 8px;
              padding: 1.25rem; overflow: auto; white-space: pre-wrap; word-break: break-word; }
        .hint { margin-top: 1.5rem; color: #888; }
      </style>
    </head>
    <body>
      <div class="wrap">
        <h1>#{escape(title)}</h1>
        <p class="sub">masthead preview · fix the issue below and refresh</p>
        <pre>#{escape(detail)}</pre>
        <p class="hint">This page is shown by the preview server, not your theme.</p>
      </div>
    </body>
    </html>
    """
  end

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
