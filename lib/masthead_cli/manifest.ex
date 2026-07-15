defmodule MastheadCli.Manifest do
  @moduledoc """
  Parses and validates a theme's `manifest.json` — a faithful copy of
  `Masthead.Themes.Manifest`, so the CLI validates with exactly the same rules
  the platform enforces on upload.

  A manifest declares the theme's identity (name, slug, version, author,
  description) and the site-wide `tokens` it exposes. Field types:

    * `color` / `string` / `length` / `number` / `select` / `boolean` — scalars
    * `file`   — a picker over the site's uploads; in production the stored
      value is the upload **id**, resolved to a URL at render time. In the CLI
      preview there are no uploads, so the value is used directly as a path/URL.
    * `text` / `url` — extra scalar inputs.
    * `object` / `list` — container fields: a group, or a repeatable group, of
      nested scalar fields (one level deep).

  Tokens and page metadata share one type set: anything a metadata field can
  declare, a token can declare too. The only difference is what the value is
  *for* — a scalar token also becomes a CSS custom property (`--accent`), while
  `object`/`list` tokens are template-only (they have no CSS representation, so
  the renderer skips them when composing the `:root` block).

  Per-page settings live in sidecar `templates/pages/<name>.json` files,
  parsed by `parse_page_config/1`.
  """

  @scalar_field_types ~w(color string length number file select boolean text url)
  @container_field_types ~w(object list)
  @field_types @scalar_field_types ++ @container_field_types

  @slug_re ~r/^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$/
  @token_key_re ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [:name, :slug, :version, :tokens]
  defstruct [
    :name,
    :slug,
    :version,
    :author,
    :description,
    tokens: [],
    metadata: []
  ]

  # A token *is* a field — same declaration, same types, same validator.
  @type token :: metadata_field()

  @type metadata_field :: %{
          key: String.t(),
          label: String.t(),
          type: String.t(),
          default: term(),
          description: String.t() | nil,
          options: [String.t()] | nil,
          category: String.t() | nil,
          fields: [metadata_field()] | nil,
          item_label: String.t() | nil
        }

  @type page_config :: %{
          label: String.t() | nil,
          description: String.t() | nil,
          metadata: [metadata_field()]
        }

  @type t :: %__MODULE__{
          name: String.t(),
          slug: String.t(),
          version: String.t(),
          author: String.t() | nil,
          description: String.t() | nil,
          tokens: [token()],
          metadata: [metadata_field()]
        }

  @spec parse(String.t()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> from_map(map)
      {:ok, _} -> {:error, ["manifest must be a JSON object"]}
      {:error, %Jason.DecodeError{} = e} -> {:error, ["invalid JSON: " <> Exception.message(e)]}
    end
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, [String.t()]}
  def from_map(map) when is_map(map) do
    errors =
      []
      |> require_string(map, "name", 1, 100)
      |> require_slug(map, "slug")
      |> require_string(map, "version", 1, 32)
      |> optional_string(map, "author", 0, 100)
      |> optional_string(map, "description", 0, 500)
      |> validate_tokens(map)
      |> validate_metadata(map)

    case errors do
      [] ->
        manifest = %__MODULE__{
          name: map["name"],
          slug: map["slug"],
          version: map["version"],
          author: map["author"],
          description: map["description"],
          tokens: normalize_fields(Map.get(map, "tokens", [])),
          metadata: normalize_fields(Map.get(map, "metadata", []))
        }

        {:ok, manifest}

      errs ->
        {:error, Enum.reverse(errs)}
    end
  end

  @doc """
  Merge of token defaults with per-site overrides.

  Tokens use the same field types (and the same coercion) as metadata, so an
  `object` token merges against its nested defaults and a `list` token comes
  back as a list of merged maps. Unknown override keys are dropped (a token is
  inert without a declaration), and a blank scalar override falls back to the
  manifest default.
  """
  @spec effective_tokens(t(), map()) :: %{String.t() => term()}
  def effective_tokens(%__MODULE__{tokens: tokens}, overrides) when is_map(overrides) do
    Enum.reduce(tokens, %{}, fn field, acc ->
      value =
        case Map.get(overrides, field.key) do
          v when v in [nil, ""] -> default_value(field)
          v -> merge_value(field, v)
        end

      Map.put(acc, field.key, value)
    end)
  end

  @doc "Merge of global metadata defaults with per-page overrides."
  @spec effective_metadata(t(), map()) :: %{String.t() => term()}
  def effective_metadata(%__MODULE__{metadata: fields}, overrides) when is_map(overrides) do
    merge_fields(fields, overrides)
  end

  @doc """
  Merge a metadata field list's defaults with a map of overrides, coercing
  declared fields to their type and passing unknown keys through verbatim.
  Shared by global metadata and a theme page's sidecar settings; recurses into
  `object`/`list` containers.
  """
  @spec merge_fields([metadata_field()], map()) :: %{String.t() => term()}
  def merge_fields(fields, overrides) when is_list(fields) and is_map(overrides) do
    defaults =
      Enum.reduce(fields, %{}, fn field, acc -> Map.put(acc, field.key, default_value(field)) end)

    field_index = Map.new(fields, fn f -> {f.key, f} end)

    Enum.reduce(overrides, defaults, fn {k, v}, acc ->
      case Map.get(field_index, k) do
        nil -> Map.put(acc, k, v)
        field -> Map.put(acc, k, merge_value(field, v))
      end
    end)
  end

  defp default_value(%{type: "object", fields: nested}) when is_list(nested),
    do: merge_fields(nested, %{})

  defp default_value(%{type: "list", fields: nested, default: items})
       when is_list(nested) and is_list(items) and items != [],
       do: Enum.map(items, fn item -> merge_fields(nested, item_map(item)) end)

  defp default_value(%{type: "list"}), do: []
  defp default_value(%{type: type, default: default}), do: coerce_metadata_value(type, default)

  defp merge_value(%{type: "object", fields: nested}, v) when is_list(nested) and is_map(v),
    do: merge_fields(nested, v)

  defp merge_value(%{type: "object", fields: nested}, _v) when is_list(nested),
    do: merge_fields(nested, %{})

  defp merge_value(%{type: "list", fields: nested}, items)
       when is_list(nested) and is_list(items),
       do: Enum.map(items, fn item -> merge_fields(nested, item_map(item)) end)

  defp merge_value(%{type: "list"}, _v), do: []
  defp merge_value(%{type: type}, v), do: coerce_metadata_value(type, v)

  defp item_map(item) when is_map(item), do: item
  defp item_map(_), do: %{}

  defp coerce_metadata_value("boolean", v) when is_boolean(v), do: v
  defp coerce_metadata_value("boolean", v) when v in ["true", "on", "1", 1], do: true
  defp coerce_metadata_value("boolean", _), do: false
  defp coerce_metadata_value("number", v) when is_number(v), do: v

  defp coerce_metadata_value("number", v) when is_binary(v) do
    case Float.parse(v) do
      {n, ""} -> if n == trunc(n), do: trunc(n), else: n
      _ -> v
    end
  end

  defp coerce_metadata_value(_type, v), do: v

  # ---- page config (templates/pages/<name>.json) ----

  @doc """
  Parse a theme page's sidecar config (`{"label"?, "description"?, "metadata"?}`)
  from a JSON-encoded binary. No version; `metadata` reuses field validation.
  """
  @spec parse_page_config(String.t()) :: {:ok, page_config()} | {:error, [String.t()]}
  def parse_page_config(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> from_page_map(map)
      {:ok, _} -> {:error, ["page config must be a JSON object"]}
      {:error, %Jason.DecodeError{} = e} -> {:error, ["invalid JSON: " <> Exception.message(e)]}
    end
  end

  @doc "Build a page config from an already-decoded map."
  @spec from_page_map(map()) :: {:ok, page_config()} | {:error, [String.t()]}
  def from_page_map(map) when is_map(map) do
    errors =
      []
      |> optional_string(map, "label", 0, 100)
      |> optional_string(map, "description", 0, 500)
      |> validate_metadata(map)

    case errors do
      [] ->
        {:ok,
         %{
           label: map["label"],
           description: map["description"],
           metadata: normalize_fields(Map.get(map, "metadata", []))
         }}

      errs ->
        {:error, Enum.reverse(errs)}
    end
  end

  # ---- internal validators ----

  defp require_string(errors, map, key, min, max) do
    case Map.get(map, key) do
      v when is_binary(v) ->
        len = String.length(v)

        cond do
          len < min -> ["#{key}: must be at least #{min} chars" | errors]
          len > max -> ["#{key}: must be at most #{max} chars" | errors]
          true -> errors
        end

      nil ->
        ["#{key}: is required" | errors]

      _ ->
        ["#{key}: must be a string" | errors]
    end
  end

  defp optional_string(errors, map, key, _min, max) do
    case Map.get(map, key) do
      nil ->
        errors

      v when is_binary(v) ->
        if String.length(v) > max do
          ["#{key}: must be at most #{max} chars" | errors]
        else
          errors
        end

      _ ->
        ["#{key}: must be a string" | errors]
    end
  end

  defp require_slug(errors, map, key) do
    case Map.get(map, key) do
      v when is_binary(v) ->
        if Regex.match?(@slug_re, v) do
          errors
        else
          ["#{key}: must be 1-32 chars, lowercase letters/digits/hyphens" | errors]
        end

      nil ->
        ["#{key}: is required" | errors]

      _ ->
        ["#{key}: must be a string" | errors]
    end
  end

  defp validate_tokens(errors, map) do
    case Map.get(map, "tokens", []) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {tok, idx}, acc ->
          validate_field(acc, tok, "tokens[#{idx}]")
        end)

      _ ->
        ["tokens: must be a list" | errors]
    end
  end

  defp validate_metadata(errors, map) do
    case Map.get(map, "metadata", []) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {field, idx}, acc ->
          validate_field(acc, field, "metadata[#{idx}]")
        end)

      _ ->
        ["metadata: must be a list" | errors]
    end
  end

  # The one validator shared by tokens, metadata, and page-config fields.
  # `allow_container?` is true at the top level and false for nested fields.
  defp validate_field(errors, field, prefix, allow_container? \\ true)

  defp validate_field(errors, field, prefix, allow_container?) when is_map(field) do
    errors =
      case Map.get(field, "key") do
        k when is_binary(k) ->
          if Regex.match?(@token_key_re, k) do
            errors
          else
            ["#{prefix}.key: must match #{inspect(@token_key_re.source)}" | errors]
          end

        _ ->
          ["#{prefix}.key: is required and must be a string" | errors]
      end

    errors =
      case Map.get(field, "label") do
        l when is_binary(l) and l != "" -> errors
        _ -> ["#{prefix}.label: is required and must be a non-empty string" | errors]
      end

    type = Map.get(field, "type")
    valid_types = if allow_container?, do: @field_types, else: @scalar_field_types

    errors =
      cond do
        type not in valid_types ->
          ["#{prefix}.type: must be one of #{Enum.join(valid_types, ", ")}" | errors]

        type == "select" and
            (not is_list(Map.get(field, "options")) or Map.get(field, "options") == []) ->
          ["#{prefix}.options: select fields require a non-empty options list" | errors]

        true ->
          errors
      end

    cond do
      type in @container_field_types ->
        validate_container_fields(errors, field, prefix)

      Map.has_key?(field, "default") ->
        errors

      true ->
        ["#{prefix}.default: is required" | errors]
    end
  end

  defp validate_field(errors, _, prefix, _allow_container?),
    do: ["#{prefix}: must be an object" | errors]

  defp validate_container_fields(errors, field, prefix) do
    case Map.get(field, "fields") do
      [_ | _] = fields ->
        fields
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {f, i}, acc ->
          validate_field(acc, f, "#{prefix}.fields[#{i}]", false)
        end)

      _ ->
        [
          "#{prefix}.fields: #{Map.get(field, "type")} fields require a non-empty fields list"
          | errors
        ]
    end
  end

  # One normalizer for tokens, metadata and page-config fields.
  defp normalize_fields(list) when is_list(list) do
    Enum.map(list, fn field ->
      %{
        key: field["key"],
        label: field["label"],
        type: field["type"],
        default: field["default"],
        description: field["description"],
        options: field["options"],
        category: field["category"],
        item_label: field["item_label"],
        fields: normalize_nested(field["fields"])
      }
    end)
  end

  defp normalize_nested(list) when is_list(list), do: normalize_fields(list)
  defp normalize_nested(_), do: nil
end
