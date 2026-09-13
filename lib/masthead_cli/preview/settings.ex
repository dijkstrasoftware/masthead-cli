defmodule MastheadCli.Preview.Settings do
  @moduledoc """
  The preview settings store — `preview.local.json` in the theme directory.

  The settings sidebar writes every token, page option and post option it edits
  into this file, and the preview server reads it back on the next request, so a
  change re-renders the *actual* page rather than poking at CSS. It is a
  **preview-only scratchpad**: nothing here is uploaded, applied, or otherwise
  visible to the platform.

      {
        "tokens": {
          "accent": "#d9480f",
          "hero":   { "title": "Welcome" },
          "links":  [ { "label": "Docs", "url": "/docs" } ]
        },
        "pages": {
          "home": { "page_options": { "hero": { "title": "Hi" } } }
        },
        "posts": {
          "hello-world": { "post_options": { "featured_image": "cover.jpg" } }
        },
        "content": {
          "posts": [ { "title": "Hello world", "slug": "hello-world", "body": "Hi." } ]
        }
      }

  It layers *over* the hand-authored `preview.json` (which stays the committed
  seed and is never rewritten): a token key set here wins over the same key
  there, and a page's or post's option key wins over its seeded value.

  The file is machine-written, so it belongs in `.gitignore` —
  `ensure_gitignored/1` adds it for you.
  """

  @filename "preview.local.json"

  @doc "Absolute path of the settings file for a theme directory."
  def path(dir), do: Path.join(dir, @filename)

  @doc "The file name, for messages and .gitignore entries."
  def filename, do: @filename

  @doc """
  Read the stored settings. A missing, unreadable or malformed file reads as
  empty — a scratchpad is never worth crashing the preview over.
  """
  @spec load(String.t()) :: %{tokens: map(), pages: map(), posts: map(), content: map()}
  def load(dir) do
    with {:ok, contents} <- File.read(path(dir)),
         {:ok, %{} = json} <- Jason.decode(contents) do
      %{
        tokens: map_at(json, "tokens"),
        pages: map_at(json, "pages"),
        posts: map_at(json, "posts"),
        content: map_at(json, "content")
      }
    else
      _ -> %{tokens: %{}, pages: %{}, posts: %{}, content: %{}}
    end
  end

  @doc """
  The sidebar-authored post or page list, or `nil` when the sidebar has never
  touched content and the seed (or the built-in sample content) still owns it.
  """
  def content(%{content: content}, kind) when kind in ["posts", "pages"] do
    case Map.get(content, kind) do
      list when is_list(list) -> list
      _ -> nil
    end
  end

  def content(_settings, _kind), do: nil

  @doc """
  Replace the sidebar-authored post or page list. The sidebar sends the whole
  list, seeded from whatever was showing, so this owns the content from here on.

  Option overrides are keyed by slug, so renaming or removing an item would
  strand its values — they are dropped here rather than left to reattach
  themselves to some later item that happens to reuse the slug.
  """
  def put_content(dir, kind, items) when kind in ["posts", "pages"] and is_list(items) do
    settings = load(dir)
    slugs = MapSet.new(items, &Map.get(&1, "slug"))

    settings
    |> Map.put(:content, Map.put(settings.content, kind, items))
    |> Map.put(bucket(kind), Map.take(Map.get(settings, bucket(kind)), MapSet.to_list(slugs)))
    |> write(dir)
  end

  defp bucket("posts"), do: :posts
  defp bucket("pages"), do: :pages

  @doc """
  The stored option overrides for one page slug (`%{}` when none). A file
  written before page options were named reads its legacy `"metadata"` key.
  """
  def page_options(%{pages: pages}, slug) when is_binary(slug), do: options_at(pages, slug)
  def page_options(_settings, _slug), do: %{}

  @doc "The stored option overrides for one post slug (`%{}` when none)."
  def post_options(%{posts: posts}, slug) when is_binary(slug), do: options_at(posts, slug)
  def post_options(_settings, _slug), do: %{}

  @doc """
  Replace the token overrides, canonicalized against the manifest's token
  fields. Returns the settings as written.
  """
  def put_tokens(dir, tokens, fields) when is_map(tokens) do
    dir
    |> load()
    |> Map.put(:tokens, canonicalize(tokens, fields))
    |> write(dir)
  end

  @doc "Replace one page's option overrides, canonicalized against its fields."
  def put_page_options(dir, slug, options, fields) when is_binary(slug) and is_map(options) do
    put_options(dir, :pages, "page_options", slug, options, fields)
  end

  @doc "Replace one post's option overrides, canonicalized against its fields."
  def put_post_options(dir, slug, options, fields) when is_binary(slug) and is_map(options) do
    put_options(dir, :posts, "post_options", slug, options, fields)
  end

  defp put_options(dir, bucket, key, slug, options, fields) do
    settings = load(dir)
    stored = Map.put(Map.get(settings, bucket), slug, %{key => canonicalize(options, fields)})

    settings
    |> Map.put(bucket, stored)
    |> write(dir)
  end

  @doc "Delete the settings file, dropping every local edit."
  def reset(dir) do
    case File.rm(path(dir)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Strip what must never be persisted: the editor's per-item `_id`s, and empty
  values — they'd pin an override where the renderer would otherwise fill in the
  field's default. Empty list *items* are kept: their count and order are
  meaningful. Together this is what the platform stores, across
  `AdminLive.SettingsFields.canonicalize/2` (containers) and the content
  changeset's `normalize_options/2` (blank scalars).
  """
  def canonicalize(values, fields) when is_map(values) and is_list(fields) do
    fields
    |> Enum.reduce(values, fn field, acc ->
      key = field.key

      case {field.type, Map.get(acc, key)} do
        {"object", %{} = obj} ->
          Map.put(acc, key, strip_empty(obj))

        {"list", list} when is_list(list) ->
          Map.put(acc, key, Enum.map(list, &(&1 |> drop_id() |> strip_empty())))

        _ ->
          acc
      end
    end)
    |> strip_empty()
  end

  def canonicalize(values, _fields) when is_map(values), do: values
  def canonicalize(_values, _fields), do: %{}

  @doc """
  Add `preview.local.json` to the theme's `.gitignore` when it isn't ignored
  already. Returns `:added`, `:present`, or `{:error, reason}`.
  """
  def ensure_gitignored(dir) do
    gitignore = Path.join(dir, ".gitignore")
    existing = File.read(gitignore)

    already? =
      case existing do
        {:ok, contents} ->
          contents
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.member?(@filename)

        _ ->
          false
      end

    cond do
      already? ->
        :present

      match?({:ok, _}, existing) ->
        {:ok, contents} = existing
        separator = if String.ends_with?(contents, "\n") or contents == "", do: "", else: "\n"
        append(gitignore, contents <> separator <> @filename <> "\n")

      true ->
        append(gitignore, @filename <> "\n")
    end
  end

  # ---- internals ----

  # Write via a temp file + rename, so a preview render mid-write never reads a
  # half-serialized file.
  defp write(%{tokens: tokens, pages: pages, posts: posts, content: content} = settings, dir) do
    body = %{"tokens" => tokens, "pages" => pages, "posts" => posts, "content" => content}
    json = Jason.encode!(body, pretty: true) <> "\n"

    target = path(dir)
    tmp = target <> ".tmp"

    with :ok <- File.write(tmp, json),
         :ok <- File.rename(tmp, target) do
      settings
    else
      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  defp append(gitignore, contents) do
    case File.write(gitignore, contents) do
      :ok -> :added
      {:error, reason} -> {:error, reason}
    end
  end

  defp map_at(json, key) do
    case Map.get(json, key) do
      %{} = map -> map
      _ -> %{}
    end
  end

  defp options_at(bucket, slug) do
    case Map.get(bucket, slug) do
      %{"page_options" => %{} = options} -> options
      %{"post_options" => %{} = options} -> options
      %{"metadata" => %{} = options} -> options
      _ -> %{}
    end
  end

  defp drop_id(item) when is_map(item), do: Map.delete(item, "_id")
  defp drop_id(item), do: item

  defp strip_empty(map) when is_map(map),
    do: map |> Enum.reject(fn {_k, v} -> v in [nil, ""] end) |> Map.new()

  defp strip_empty(other), do: other
end
