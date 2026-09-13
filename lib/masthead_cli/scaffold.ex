defmodule MastheadCli.Scaffold do
  @moduledoc """
  Backs `masthead new`: clones the official starter theme and turns it
  into a fresh, independent project.

  The template lives in its own repo so it can evolve (and be previewed)
  on its own. `create/3` shallow-clones it, removes the `.git` directory
  so the new theme starts with a clean history, and rewrites the
  manifest's `name`/`slug` to match what the author asked for.
  """

  @template_repo "https://github.com/dijkstrasoftware/masthead-template.git"

  @doc "The git URL of the template that `create/3` clones."
  def template_repo, do: @template_repo

  @doc """
  Create a new theme in `dir` named `name` (slug `slug`) by cloning the
  template. Returns `:ok` or `{:error, message}`.
  """
  @spec create(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def create(dir, name, slug) do
    with :ok <- ensure_git(),
         :ok <- ensure_target_available(dir),
         :ok <- clone(dir),
         :ok <- finalize(dir, name, slug) do
      :ok
    end
  end

  @doc """
  Derive a valid theme slug (lowercase letters/digits/hyphens, 1-32 chars,
  no leading/trailing hyphen) from arbitrary input. Returns `""` when no
  usable slug can be formed.
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(input) do
    input
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.slice(0, 32)
    |> String.trim("-")
  end

  @doc "A human-readable title derived from a slug, e.g. \"my-blog\" -> \"My Blog\"."
  @spec titleize(String.t()) :: String.t()
  def titleize(slug) do
    slug
    |> String.split("-", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Rewrite a manifest JSON string's top-level `name` and `slug` values,
  preserving the rest of the file (and its formatting) verbatim.
  """
  @spec personalize_manifest(String.t(), String.t(), String.t()) :: String.t()
  def personalize_manifest(json, name, slug) do
    json
    |> put_field("name", name)
    |> put_field("slug", slug)
  end

  # ---- internals ----

  defp ensure_git do
    if System.find_executable("git") do
      :ok
    else
      {:error, "`git` is required to create a theme, but it was not found on your PATH."}
    end
  end

  defp ensure_target_available(dir) do
    if File.exists?(dir) and not empty_dir?(dir) do
      {:error, "Refusing to scaffold into #{dir} — it already exists and is not empty."}
    else
      :ok
    end
  end

  defp clone(dir) do
    case System.cmd("git", ["clone", "--quiet", "--depth", "1", @template_repo, dir],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> :ok
      {out, _code} -> {:error, "Could not clone the theme template:\n" <> String.trim(out)}
    end
  end

  # Drop the template's git history and stamp the new theme's identity into
  # the manifest. A missing manifest is left alone — `validate` will report it.
  defp finalize(dir, name, slug) do
    File.rm_rf!(Path.join(dir, ".git"))

    manifest_path = Path.join(dir, "manifest.json")

    case File.read(manifest_path) do
      {:ok, json} -> File.write!(manifest_path, personalize_manifest(json, name, slug))
      {:error, _} -> :ok
    end

    :ok
  end

  defp put_field(json, field, value) do
    Regex.replace(
      ~r/"#{field}"\s*:\s*"[^"]*"/,
      json,
      fn _ ->
        ~s("#{field}": #{Jason.encode!(value)})
      end,
      global: false
    )
  end

  defp empty_dir?(dir) do
    case File.ls(dir) do
      {:ok, entries} -> entries == []
      {:error, _} -> false
    end
  end
end
