defmodule MastheadCli.Theme do
  @moduledoc """
  Load a theme from a directory on disk: `manifest.json`, `theme.css`, and
  the six required Liquid templates under `templates/`.

  The directory layout mirrors what a Masthead theme zip contains:

      manifest.json
      theme.css
      templates/
        layout.liquid
        index.liquid
        post.liquid
        page.liquid
        blog.liquid
        not_found.liquid
      assets/            (optional — images, fonts, extra css)

  Loading is deliberately uncached: the preview server re-reads on every
  request so edits to templates, CSS, or the manifest show up on refresh.
  """

  alias MastheadCli.{Manifest, Sandbox}

  @required_templates ~w(layout index post page blog not_found)a

  @type t :: %{
          manifest: Manifest.t(),
          css: String.t(),
          templates: %{atom() => Solid.Template.t()},
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
         {:ok, templates} <- load_templates(dir) do
      {:ok,
       %{
         manifest: manifest,
         css: load_css(dir),
         templates: templates,
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
      {:ok, Map.new(results, fn {name, {:ok, template}} -> {name, template} end)}
    else
      {:error, {:templates, errors}}
    end
  end

  defp parse_error_message(%Solid.TemplateError{} = err), do: Exception.message(err)
  defp parse_error_message(other), do: inspect(other)
end
