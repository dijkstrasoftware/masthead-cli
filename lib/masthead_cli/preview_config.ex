defmodule MastheadCli.PreviewConfig do
  @moduledoc """
  Resolve the preview dataset for a theme directory, layering optional
  author overrides on top of the built-in sample content.

  Overrides are entirely optional. With none, `masthead preview` uses
  `MastheadCli.Content.Fixtures`. To customise, drop any of these into the
  theme directory:

      preview.json              site fields + token overrides (+ optional
                                inline posts/pages arrays)
      preview.local.json        the settings sidebar's scratchpad — layered on
                                top of preview.json (see `Preview.Settings`)
      preview/posts/*.md        one post per file, JSON front matter + body
      preview/pages/*.md        one page per file, JSON front matter + body

  ## preview.json

      {
        "site": {
          "name": "Acme Co.",
          "title": "Acme — we make things",
          "description": "...",
          "slug": "acme",
          "css_overrides": ".intro { letter-spacing: -0.02em; }",
          "homepage": "home"        // slug of the page to serve at "/"
        },
        "tokens": { "accent": "#d9480f", "max_width": "1120px" }
      }

  ## Markdown files (JSON front matter)

      ---
      { "title": "About", "slug": "about", "format": "markdown",
        "metadata": { "layout": "wide" }, "show_in_nav": true }
      ---
      ## About us

      Markdown body here...

  Front matter keys mirror the fixture shapes. `published_at` accepts an
  ISO-8601 datetime (`2026-01-15T09:00:00Z`) or a date (`2026-01-15`).
  Files in `preview/posts` / `preview/pages` take precedence over any
  inline `posts` / `pages` arrays in preview.json.
  """

  alias MastheadCli.Content.Fixtures
  alias MastheadCli.Preview.Settings

  @doc """
  Load the resolved `%{site, posts, pages, tags}` dataset for `dir`.

  `preview.json` (plus any `preview/posts|pages/*.md`) is the seed; the sidebar's
  `preview.local.json` is layered on top of it — a token key it sets wins over
  the seed's, and a page's stored metadata keys win over that page's seeded
  metadata. `tags` is derived from the tags the preview posts carry.
  """
  def load(dir) do
    json = read_json(dir)
    settings = Settings.load(dir)
    posts = load_posts(dir, json)

    %{
      site: build_site(json, settings),
      posts: posts,
      pages: dir |> load_pages(json) |> apply_page_settings(settings),
      tags: collect_tags(posts)
    }
  end

  # ---- site ----

  defp build_site(json, settings) do
    base = Fixtures.default_site()
    site = Map.get(json, "site", %{})

    # Structure-preserving: an `object` token's value is a map and a `list`
    # token's is a list of maps, so nothing here may flatten to strings.
    tokens = Map.merge(stringify_keys(Map.get(json, "tokens", %{})), settings.tokens)

    base
    |> maybe_put(site, "name", :name)
    |> maybe_put(site, "title", :title)
    |> maybe_put(site, "description", :description)
    |> maybe_put(site, "slug", :slug)
    |> maybe_put(site, "css_overrides", :css_overrides)
    |> maybe_put(site, "homepage", :homepage_slug)
    |> Map.put(:theme_tokens, tokens)
  end

  # The sidebar's per-page metadata overrides win, key by key, over whatever the
  # page was seeded with.
  defp apply_page_settings(pages, settings) do
    Enum.map(pages, fn page ->
      case Settings.page_metadata(settings, page.slug) do
        overrides when map_size(overrides) == 0 ->
          page

        overrides ->
          Map.put(page, :metadata, Map.merge(page.metadata || %{}, overrides))
      end
    end)
  end

  # The site's tag list: every tag its posts carry, de-duplicated, by name.
  defp collect_tags(posts) do
    posts
    |> Enum.flat_map(&(&1.tags || []))
    |> Enum.uniq_by(& &1.slug)
    |> Enum.sort_by(& &1.name)
  end

  defp maybe_put(acc, source, src_key, dest_key) do
    case Map.get(source, src_key) do
      nil -> acc
      value -> Map.put(acc, dest_key, value)
    end
  end

  # ---- posts / pages ----

  defp load_posts(dir, json) do
    case load_dir(Path.join([dir, "preview", "posts"]), &normalize_post/1) do
      [] -> inline_or_default(json, "posts", &normalize_post/1, &Fixtures.default_posts/0)
      posts -> sort_posts(posts)
    end
  end

  defp load_pages(dir, json) do
    case load_dir(Path.join([dir, "preview", "pages"]), &normalize_page/1) do
      [] -> inline_or_default(json, "pages", &normalize_page/1, &Fixtures.default_pages/0)
      pages -> sort_pages(pages)
    end
  end

  defp inline_or_default(json, key, normalize, default_fun) do
    case Map.get(json, key) do
      list when is_list(list) and list != [] ->
        list |> Enum.map(&normalize.(&1)) |> maybe_sort(key)

      _ ->
        default_fun.()
    end
  end

  defp maybe_sort(items, "posts"), do: sort_posts(items)
  defp maybe_sort(items, "pages"), do: sort_pages(items)

  # Posts list newest-first (mirrors list_published_posts: order_by published_at desc).
  defp sort_posts(posts) do
    Enum.sort_by(posts, & &1.published_at, {:desc, DateTime})
  end

  # Pages ordered by title (mirrors list_published_pages: order_by title).
  defp sort_pages(pages), do: Enum.sort_by(pages, & &1.title)

  defp load_dir(dir, normalize) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, [".md", ".markdown", ".html"]))
        |> Enum.sort()
        |> Enum.map(fn file ->
          path = Path.join(dir, file)
          {meta, body} = split_front_matter(File.read!(path))
          format_default = if String.ends_with?(file, ".html"), do: "html", else: "markdown"

          meta
          |> Map.put_new("format", format_default)
          |> Map.put_new("slug", file |> Path.rootname() |> slugify())
          |> Map.put_new("title", file |> Path.rootname() |> titleize())
          |> Map.put("body", body)
          |> normalize.()
        end)

      {:error, _} ->
        []
    end
  end

  # ---- normalizers (string-keyed map -> atom-keyed fixture map) ----

  defp normalize_post(m) do
    %{
      title: m["title"],
      slug: m["slug"],
      excerpt: m["excerpt"] || "",
      format: m["format"] || "markdown",
      published_at: parse_datetime(m["published_at"]),
      tags: normalize_tags(m["tags"]),
      body: m["body"] || ""
    }
  end

  # `"tags": ["Emacs", "Elixir"]` — names, slugged the way the platform slugs
  # them. A `{"name":…, "slug":…}` object is accepted too.
  defp normalize_tags(list) when is_list(list) do
    Enum.flat_map(list, fn
      name when is_binary(name) ->
        [%{name: name, slug: slugify(name)}]

      %{"name" => name} = t when is_binary(name) ->
        [%{name: name, slug: t["slug"] || slugify(name)}]

      _ ->
        []
    end)
  end

  defp normalize_tags(_), do: []

  defp normalize_page(m) do
    %{
      title: m["title"],
      slug: m["slug"],
      format: m["format"] || "markdown",
      # For `"format": "theme"` pages: which templates/pages/<template>.liquid.
      template: m["template"],
      show_in_nav: Map.get(m, "show_in_nav", true),
      metadata: m["metadata"] || %{},
      body: m["body"] || ""
    }
  end

  # ---- helpers ----

  defp read_json(dir) do
    path = Path.join(dir, "preview.json")

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, map} when is_map(map) ->
            map

          {:ok, _} ->
            warn("preview.json must be a JSON object — ignoring")
            %{}

          {:error, e} ->
            warn("preview.json is not valid JSON (#{Exception.message(e)}) — ignoring")
            %{}
        end

      {:error, _} ->
        %{}
    end
  end

  @doc """
  Split a markdown/html file with optional JSON front matter into
  `{meta_map, body}`. A file that doesn't start with a `---` fence is all
  body with empty meta.
  """
  def split_front_matter("---\r\n" <> rest), do: do_split(rest)
  def split_front_matter("---\n" <> rest), do: do_split(rest)
  def split_front_matter(content), do: {%{}, content}

  defp do_split(rest) do
    case String.split(rest, ~r/\r?\n---\r?\n/, parts: 2) do
      [front, body] -> {decode_front_matter(front), body}
      [_] -> {%{}, rest}
    end
  end

  defp decode_front_matter(front) do
    case Jason.decode(String.trim(front)) do
      {:ok, map} when is_map(map) ->
        map

      _ ->
        warn("front matter is not a valid JSON object — ignoring")
        %{}
    end
  end

  defp parse_datetime(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp parse_datetime(value) when is_binary(value) do
    cond do
      String.contains?(value, "T") ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _} -> DateTime.truncate(dt, :second)
          _ -> fallback_date(value)
        end

      true ->
        fallback_date(value)
    end
  end

  defp fallback_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end

  # Keys become strings (they're token keys); values are left exactly as the
  # author wrote them, so nested objects and lists survive.
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(_), do: %{}

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp titleize(name) do
    name
    |> String.replace(~r/[-_]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp warn(message), do: IO.puts(:stderr, "  ! #{message}")
end
