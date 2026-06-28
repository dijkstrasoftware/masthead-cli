defmodule MastheadCli.Theme do
  @moduledoc """
  Load a theme from a directory on disk: `manifest.json`, `theme.css`, the
  fixed Liquid templates, and any theme pages under `templates/pages/`.

  The directory layout mirrors what a Masthead theme zip contains:

      manifest.json
      theme.css
      templates/
        layout.liquid
        index.liquid
        post.liquid
        page.liquid
        not_found.liquid
        blog.liquid           (optional — legacy fixed template)
        pages/
          <name>.liquid       (a theme page)
          <name>.json         (its optional settings config)
      assets/                 (optional — images, fonts, extra css)

  Loading is deliberately uncached: the preview server re-reads on every
  request so edits to templates, CSS, the manifest, or page configs show up
  on refresh.
  """

  alias MastheadCli.{Manifest, Sandbox}

  # `blog` is no longer a required fixed template — it moved into the
  # `templates/pages/` folder as a theme page — but it's still loaded
  # optionally so themes authored before that change keep working.
  @required_templates ~w(layout index post page not_found)a
  @optional_templates ~w(blog)a

  @type t :: %{
          manifest: Manifest.t(),
          css: String.t(),
          templates: %{atom() => Solid.Template.t()},
          page_templates: %{String.t() => Solid.Template.t()},
          page_configs: %{String.t() => Manifest.page_config()},
          asset_base: String.t(),
          dir: String.t()
        }

  @doc """
  Load + parse a theme directory.

  Returns `{:ok, theme}` or `{:error, reason}` where reason is one of:

    * `{:missing, message}`        — no manifest.json
    * `{:manifest, [error, ...]}`  — manifest failed validation
    * `{:templates, [{name, error}, ...]}` — missing or unparseable templates
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(dir) do
    with {:ok, manifest} <- load_manifest(dir),
         {:ok, templates} <- load_templates(dir),
         {:ok, page_templates} <- load_page_templates(dir),
         {:ok, page_configs} <- load_page_configs(dir) do
      {:ok,
       %{
         manifest: manifest,
         css: load_css(dir),
         templates: templates,
         page_templates: page_templates,
         page_configs: page_configs,
         asset_base: "/assets",
         dir: dir
       }}
    end
  end

  @doc "True if `dir` looks like a theme directory (has a manifest.json)."
  def theme_dir?(dir), do: File.exists?(Path.join(dir, "manifest.json"))

  defp load_manifest(dir) do
    path = Path.join(dir, "manifest.json")

    case File.read(path) do
      {:ok, json} ->
        case Manifest.parse(json) do
          {:ok, manifest} -> {:ok, manifest}
          {:error, errors} -> {:error, {:manifest, errors}}
        end

      {:error, _} ->
        {:error, {:missing, "no manifest.json found in #{dir}"}}
    end
  end

  # theme.css is required by the platform but tolerated-as-empty here so a
  # half-built theme still previews.
  defp load_css(dir) do
    case File.read(Path.join(dir, "theme.css")) do
      {:ok, css} -> css
      {:error, _} -> ""
    end
  end

  defp load_templates(dir) do
    results =
      Enum.map(@required_templates, fn name ->
        path = Path.join([dir, "templates", "#{name}.liquid"])

        result =
          case File.read(path) do
            {:ok, source} ->
              case Sandbox.parse(source) do
                {:ok, template} -> {:ok, template}
                {:error, err} -> {:error, parse_error_message(err)}
              end

            {:error, _} ->
              {:error, "missing templates/#{name}.liquid"}
          end

        {name, result}
      end)

    errors = for {name, {:error, msg}} <- results, do: {name, msg}

    if errors == [] do
      required = Map.new(results, fn {name, {:ok, template}} -> {name, template} end)
      {:ok, load_optional_templates(dir, required)}
    else
      {:error, {:templates, errors}}
    end
  end

  # Optional fixed templates (e.g. legacy `blog`) load only when present.
  defp load_optional_templates(dir, acc) do
    Enum.reduce(@optional_templates, acc, fn name, acc ->
      path = Path.join([dir, "templates", "#{name}.liquid"])

      with {:ok, source} <- File.read(path),
           {:ok, template} <- Sandbox.parse(source) do
        Map.put(acc, name, template)
      else
        _ -> acc
      end
    end)
  end

  # Page templates live in `templates/pages/<name>.liquid`. Names are author
  # filenames, so they stay STRING-keyed (never `String.to_atom/1`).
  defp load_page_templates(dir) do
    page_dir = Path.join([dir, "templates", "pages"])

    page_dir
    |> Path.join("*.liquid")
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      name = Path.basename(path, ".liquid")

      case File.read(path) do
        {:ok, source} ->
          case Sandbox.parse(source) do
            {:ok, template} ->
              {:cont, {:ok, Map.put(acc, name, template)}}

            {:error, err} ->
              {:halt, {:error, {:templates, [{"pages/#{name}", parse_error_message(err)}]}}}
          end

        {:error, _} ->
          {:halt, {:error, {:templates, [{"pages/#{name}", "unreadable"}]}}}
      end
    end)
  end

  # Each page template may carry a sidecar `templates/pages/<name>.json`
  # describing its editable settings (the page config). Optional; a
  # present-but-invalid one is reported like a bad manifest.
  defp load_page_configs(dir) do
    page_dir = Path.join([dir, "templates", "pages"])

    page_dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      name = Path.basename(path, ".json")

      case File.read(path) do
        {:ok, json} ->
          case Manifest.parse_page_config(json) do
            {:ok, config} -> {:cont, {:ok, Map.put(acc, name, config)}}
            {:error, errors} -> {:halt, {:error, {:page_config, name, errors}}}
          end

        {:error, _} ->
          {:cont, {:ok, acc}}
      end
    end)
  end

  defp parse_error_message(%Solid.TemplateError{} = err), do: Exception.message(err)
  defp parse_error_message(other), do: inspect(other)
end
