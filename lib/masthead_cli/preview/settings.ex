defmodule MastheadCli.Preview.Settings do
  @moduledoc """
  The preview settings store — `preview.local.json` in the theme directory.

  The settings sidebar writes every token and page-metadata value it edits into
  this file, and the preview server reads it back on the next request, so a
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
          "home": { "metadata": { "hero": { "title": "Hi" } } }
        }
      }

  It layers *over* the hand-authored `preview.json` (which stays the committed
  seed and is never rewritten): a token key set here wins over the same key
  there, and a page's metadata key wins over that page's seeded metadata.

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
  @spec load(String.t()) :: %{tokens: map(), pages: map()}
  def load(dir) do
    with {:ok, contents} <- File.read(path(dir)),
         {:ok, %{} = json} <- Jason.decode(contents) do
      %{tokens: map_at(json, "tokens"), pages: map_at(json, "pages")}
    else
      _ -> %{tokens: %{}, pages: %{}}
    end
  end

  @doc "The stored metadata overrides for one page slug (`%{}` when none)."
  def page_metadata(%{pages: pages}, slug) when is_binary(slug) do
    case Map.get(pages, slug) do
      %{"metadata" => %{} = metadata} -> metadata
      _ -> %{}
    end
  end

  def page_metadata(_settings, _slug), do: %{}

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

  @doc "Replace one page's metadata overrides, canonicalized against its fields."
  def put_page_metadata(dir, slug, metadata, fields) when is_binary(slug) and is_map(metadata) do
    settings = load(dir)
    pages = Map.put(settings.pages, slug, %{"metadata" => canonicalize(metadata, fields)})

    settings
    |> Map.put(:pages, pages)
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
  subvalues inside containers (they'd pin an override where the renderer would
  otherwise fill in the field's default). Empty list *items* are kept — their
  count and order are meaningful. Mirrors the platform's
  `AdminLive.SettingsFields.canonicalize/2`.
  """
  def canonicalize(values, fields) when is_map(values) and is_list(fields) do
    Enum.reduce(fields, values, fn field, acc ->
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
  defp write(%{tokens: tokens, pages: pages} = settings, dir) do
    json = Jason.encode!(%{"tokens" => tokens, "pages" => pages}, pretty: true) <> "\n"
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

  defp drop_id(item) when is_map(item), do: Map.delete(item, "_id")
  defp drop_id(item), do: item

  defp strip_empty(map) when is_map(map),
    do: map |> Enum.reject(fn {_k, v} -> v in [nil, ""] end) |> Map.new()

  defp strip_empty(other), do: other
end
