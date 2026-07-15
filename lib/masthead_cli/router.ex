defmodule MastheadCli.Router do
  @moduledoc """
  The preview HTTP router — a plain Plug serving two things.

  **The theme**, at exactly the routes the platform serves it at
  (`MastheadWeb.PublicRouter` / `PublicController`):

      GET /              -> the homepage page (if configured) else the post list
      GET /posts/:slug   -> a single post, or the themed 404
      GET /search?q=     -> the search results page
      GET /:slug         -> a page (markdown/html/theme), or the themed 404
      GET /assets/*path  -> static files from the theme's assets/ folder

  **The editor**, under `/__preview`: the shell that frames the theme next to
  the settings sidebar, the JSON state the sidebar is built from, the endpoint it
  writes settings through, and the SSE stream that pushes a reload when a theme
  file changes on disk.

  The theme and the preview dataset are re-read on every request, so a change to
  a template, the CSS, the manifest, the preview content or the settings file
  shows up on the next render. Load and render errors are shown as an in-browser
  diagnostic page rather than crashing the connection.
  """

  @behaviour Plug

  import Plug.Conn

  alias MastheadCli.{Content, PreviewConfig, Renderer, Term, Theme}
  alias MastheadCli.Preview.{Chrome, Events, Settings, State}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    dir = Keyword.fetch!(opts, :dir)
    editor? = Keyword.get(opts, :editor, true)

    # The request log is the running server's UI; tests turn it off.
    conn =
      conn
      |> fetch_query_params()
      |> put_private(:mh_log, Keyword.get(opts, :log, true))

    case conn.path_info do
      ["__preview" | rest] when editor? -> editor(conn, dir, rest)
      ["assets" | rest] -> asset(conn, dir, rest)
      _ -> theme(conn, dir, editor?)
    end
  end

  # ---- the editor ----

  defp editor(conn, _dir, []) do
    path = conn.query_params["path"] || "/"
    html(conn, 200, Chrome.page(safe_path(path)))
  end

  defp editor(conn, dir, ["state"]) do
    path = safe_path(conn.query_params["path"] || "/")

    case Theme.load(dir) do
      {:ok, theme} ->
        json(conn, 200, State.build(theme, PreviewConfig.load(dir), dir, path))

      {:error, reason} ->
        json(conn, 500, %{error: format_load_error(reason)})
    end
  end

  defp editor(%{method: "POST"} = conn, dir, ["settings"]) do
    {:ok, raw, conn} = read_body(conn)

    with {:ok, %{} = payload} <- Jason.decode(raw),
         {:ok, theme} <- Theme.load(dir) do
      write_settings(dir, theme, payload)
      send_resp(conn, 204, "")
    else
      _ -> json(conn, 400, %{error: "could not apply settings"})
    end
  end

  defp editor(%{method: "POST"} = conn, dir, ["reset"]) do
    Settings.reset(dir)
    send_resp(conn, 204, "")
  end

  defp editor(conn, _dir, ["events"]) do
    Events.subscribe()

    conn
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/event-stream")
    |> send_chunked(200)
    |> stream_events()
  end

  defp editor(conn, _dir, _rest), do: send_resp(conn, 404, "not found")

  # The sidebar owns the values and posts them whole, so a write is a replace,
  # not a merge — canonicalized against the schema the values belong to (which is
  # where the editor's per-item ids and empty subvalues get dropped).
  defp write_settings(dir, theme, payload) do
    case Map.get(payload, "tokens") do
      %{} = tokens -> Settings.put_tokens(dir, tokens, theme.manifest.tokens)
      _ -> :ok
    end

    case Map.get(payload, "page") do
      %{"slug" => slug, "metadata" => %{} = metadata} when is_binary(slug) ->
        Settings.put_page_metadata(dir, slug, metadata, page_fields(theme, dir, slug))

      _ ->
        :ok
    end
  end

  defp page_fields(theme, dir, slug) do
    data = PreviewConfig.load(dir)

    case Enum.find(data.pages, &(&1.slug == slug)) do
      %{format: "theme", template: template} when is_binary(template) ->
        case Map.get(theme.page_configs, template) do
          %{metadata: fields} when is_list(fields) -> fields
          _ -> []
        end

      %{} ->
        theme.manifest.metadata

      nil ->
        []
    end
  end

  # One SSE connection per open tab; it lives until the browser goes away.
  # `:reload` arrives from the watcher (see `Preview.Events`).
  defp stream_events(conn) do
    receive do
      :reload ->
        case chunk(conn, "event: reload\ndata: 1\n\n") do
          {:ok, conn} -> stream_events(conn)
          {:error, :closed} -> conn
        end
    end
  end

  # ---- the theme ----

  defp theme(conn, dir, editor?) do
    case Theme.load(dir) do
      {:ok, theme} ->
        data = PreviewConfig.load(dir)

        response =
          try do
            dispatch(theme, data, conn)
          rescue
            e -> {:error_page, 500, "Render error", Exception.format(:error, e, __STACKTRACE__)}
          end

        send_theme(conn, response, editor?)

      {:error, reason} ->
        send_theme(
          conn,
          {:error_page, 500, "Theme failed to load", format_load_error(reason)},
          editor?
        )
    end
  end

  defp dispatch(theme, data, conn) do
    case conn.path_info do
      [] -> index(theme, data, conn)
      ["posts", slug] -> post(theme, data, slug)
      ["search"] -> search(theme, data, conn)
      [slug] -> page(theme, data, slug)
      _ -> not_found(theme, data)
    end
  end

  defp index(theme, data, conn) do
    case homepage(data) do
      nil ->
        current = current_tag(data, conn)
        posts = filter_by_tag(data.posts, current)

        {:ok, 200,
         Renderer.render_index(theme, %{
           site: data.site,
           posts: posts,
           all_posts: data.posts,
           pages: nav_pages(data),
           tags: data.tags,
           current_tag: current
         })}

      page ->
        render_page_target(theme, data, page, conn)
    end
  end

  defp post(theme, data, slug) do
    case Enum.find(data.posts, &(&1.slug == slug)) do
      nil ->
        not_found(theme, data)

      post ->
        {:ok, 200,
         Renderer.render_post(
           theme,
           Map.merge(
             %{
               site: data.site,
               post: post,
               all_posts: data.posts,
               pages: nav_pages(data)
             },
             body_assigns(post)
           )
         )}
    end
  end

  defp search(theme, data, conn) do
    query = conn.query_params["q"] || ""

    matches =
      case String.trim(query) do
        "" ->
          data.posts

        trimmed ->
          needle = String.downcase(trimmed)

          Enum.filter(data.posts, fn post ->
            String.contains?(String.downcase(post.title || ""), needle) or
              String.contains?(String.downcase(post.excerpt || ""), needle)
          end)
      end

    {:ok, 200,
     Renderer.render_search(theme, %{
       site: data.site,
       posts: matches,
       all_posts: data.posts,
       pages: nav_pages(data),
       query: query
     })}
  end

  defp page(theme, data, slug) do
    case Enum.find(data.pages, &(&1.slug == slug)) do
      nil -> not_found(theme, data)
      page -> render_page_target(theme, data, page, nil)
    end
  end

  defp not_found(theme, data) do
    {:ok, 404,
     Renderer.render_not_found(theme, %{
       site: data.site,
       all_posts: data.posts,
       pages: nav_pages(data)
     })}
  end

  # A theme page renders its `templates/pages/<template>.liquid` with the full
  # post list (so a blog page can list them, filtered by `?tag=`); everything
  # else renders as a plain page. Mirrors PublicController.
  defp render_page_target(theme, data, %{format: "theme"} = page, conn) do
    current = current_tag(data, conn)

    {:ok, 200,
     Renderer.render_theme_page(theme, %{
       site: data.site,
       page: page,
       posts: filter_by_tag(data.posts, current),
       all_posts: data.posts,
       pages: nav_pages(data),
       tags: data.tags,
       current_tag: current
     })}
  end

  defp render_page_target(theme, data, page, _conn) do
    {:ok, 200,
     Renderer.render_page(
       theme,
       Map.merge(
         %{
           site: data.site,
           page: page,
           all_posts: data.posts,
           pages: nav_pages(data)
         },
         body_assigns(page)
       )
     )}
  end

  # An `html` body is Liquid, rendered against the page's own context and left
  # unsanitized (the author is trusted); anything else is markdown, pre-rendered
  # and scrubbed. Same split as the platform's controller.
  defp body_assigns(%{format: "html"} = content), do: %{liquid_body: content.body || ""}

  defp body_assigns(content),
    do: %{body_html: Content.render_body(content.body, content.format)}

  # The nav excludes the designated homepage and anything hidden from it.
  defp nav_pages(%{site: site, pages: pages}) do
    home = Map.get(site, :homepage_slug)

    Enum.reject(pages, fn page ->
      page.slug == home or Map.get(page, :show_in_nav) == false
    end)
  end

  defp homepage(%{site: site, pages: pages}) do
    case Map.get(site, :homepage_slug) do
      nil -> nil
      slug -> Enum.find(pages, &(&1.slug == slug))
    end
  end

  defp current_tag(data, conn) do
    with %Plug.Conn{} <- conn,
         slug when is_binary(slug) <- conn.query_params["tag"] do
      Enum.find(data.tags, &(&1.slug == slug))
    else
      _ -> nil
    end
  end

  defp filter_by_tag(posts, nil), do: posts

  defp filter_by_tag(posts, tag) do
    Enum.filter(posts, fn post ->
      Enum.any?(post.tags || [], &(&1.slug == tag.slug))
    end)
  end

  # ---- responses ----

  defp send_theme(conn, {:ok, status, body}, editor?) do
    body = if editor?, do: Chrome.inject(body), else: body
    html(conn, status, body)
  end

  defp send_theme(conn, {:error_page, status, title, detail}, _editor?) do
    html(conn, status, error_page(title, detail))
  end

  defp asset(conn, dir, rest) do
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

  defp html(conn, status, body) do
    log(conn, status)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  # The shell only ever frames this server's own routes.
  defp safe_path("/" <> _ = path), do: path
  defp safe_path(_path), do: "/"

  defp log(conn, status) do
    if conn.private[:mh_log] do
      path = "/" <> Enum.join(conn.path_info, "/")
      IO.puts("  #{Term.status(status)}  #{Term.dim(conn.method)} #{path}")
    end
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

  defp format_load_error({:page_config, name, errors}) do
    "templates/pages/#{name}.json is invalid:\n\n" <>
      Enum.map_join(errors, "\n", &("  • " <> &1))
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
        <p class="sub">masthead preview · fix the issue below; the page reloads itself</p>
        <pre>#{escape(detail)}</pre>
        <p class="hint">This page is shown by the preview server, not your theme.</p>
      </div>
      <script>
        var events = new EventSource("/__preview/events");
        events.addEventListener("reload", function () { window.location.reload(); });
      </script>
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
