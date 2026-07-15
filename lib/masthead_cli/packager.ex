defmodule MastheadCli.Packager do
  @moduledoc """
  Bundle a theme directory into an installable Masthead theme zip.

  The archive contains exactly what the platform's `Masthead.Themes.Package`
  consumes on upload — and nothing else:

      manifest.json
      theme.css
      templates/{layout,index,post,page,not_found}.liquid
      templates/pages/*.liquid + *.json   (theme pages + their settings)
      assets/…            (only whitelisted extensions, no symlinks)

  Dev-only files are deliberately excluded: `preview/`, `preview.json`,
  `preview.local.json`, `README.md`, `.git`, `.DS_Store`, any stray `*.zip`, etc. The theme is
  validated first (manifest + all templates + page configs parse) so we never
  ship a broken bundle, and the platform's upload caps are checked so you find
  out here rather than at upload time.
  """

  alias MastheadCli.Theme

  # Mirrors Masthead.Themes.Package's asset extension whitelist and caps.
  @asset_exts ~w(.css .png .jpg .jpeg .gif .webp .svg .woff .woff2 .ttf .otf .ico .json)
  @reserved_slugs ~w(default studio tailwind)
  @max_zip_bytes 5 * 1024 * 1024
  @max_uncompressed_bytes 25 * 1024 * 1024
  @max_files 200

  # Accepted --bump levels; "patch" is a synonym for "bugfix".
  @bump_levels ~w(major minor bugfix patch)

  @type summary :: %{
          path: String.t(),
          slug: String.t(),
          version: String.t(),
          bump: %{level: String.t(), from: String.t(), to: String.t()} | nil,
          file_count: non_neg_integer(),
          uncompressed: non_neg_integer(),
          zip_bytes: non_neg_integer(),
          warnings: [String.t()]
        }

  @doc """
  Package the theme in `dir`, writing the zip to `out` (a `.zip` file path,
  a directory, or `nil` for the default — `~/Desktop`, falling back to the
  home directory).

  `bump` optionally bumps the manifest's SemVer **in place** before
  packaging (`"major"`, `"minor"`, or `"bugfix"`/`"patch"`; `nil` leaves it
  alone). The version field in `manifest.json` is rewritten on disk, and
  the zip is named with the new version. The bump happens only after the
  theme validates, so a broken theme never gets its version touched.

  Returns `{:ok, summary}` or `{:error, message}`.
  """
  @spec package(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, summary()} | {:error, String.t()}
  def package(dir, out, bump \\ nil) do
    with {:ok, theme} <- load(dir),
         {:ok, bump_info} <- maybe_bump(dir, theme.manifest, bump),
         manifest = bumped_manifest(theme.manifest, bump_info),
         {entries, warnings} <- collect(dir),
         {:ok, path} <- resolve_out(out, manifest),
         :ok <- write_zip(path, entries) do
      {:ok,
       %{
         path: path,
         slug: manifest.slug,
         version: manifest.version,
         bump: bump_info,
         file_count: length(entries),
         uncompressed: total_bytes(entries),
         zip_bytes: File.stat!(path).size,
         warnings: warnings ++ cap_warnings(entries, path) ++ slug_warnings(manifest)
       }}
    end
  end

  # ---- version bump ----

  defp maybe_bump(_dir, _manifest, nil), do: {:ok, nil}

  defp maybe_bump(dir, manifest, level) when level in @bump_levels do
    case Version.parse(manifest.version) do
      {:ok, version} ->
        new = next_version(version, level)

        case rewrite_version(dir, new) do
          :ok -> {:ok, %{level: level, from: manifest.version, to: new}}
          {:error, _} = error -> error
        end

      :error ->
        {:error,
         "current version #{inspect(manifest.version)} is not valid SemVer — cannot --bump"}
    end
  end

  defp maybe_bump(_dir, _manifest, level),
    do: {:error, "unknown --bump level #{inspect(level)} — use major, minor, or bugfix"}

  defp next_version(%Version{major: maj}, "major"), do: "#{maj + 1}.0.0"
  defp next_version(%Version{major: maj, minor: min}, "minor"), do: "#{maj}.#{min + 1}.0"

  defp next_version(%Version{major: maj, minor: min, patch: patch}, _bugfix),
    do: "#{maj}.#{min}.#{patch + 1}"

  # Rewrite just the top-level "version" string, preserving the rest of the
  # author's formatting (a JSON round-trip would reorder keys).
  defp rewrite_version(dir, new) do
    path = Path.join(dir, "manifest.json")
    raw = File.read!(path)
    # Function form avoids backreference ambiguity (e.g. `\\1` + a new
    # version starting with a digit being read as group 11).
    updated =
      Regex.replace(
        ~r/("version"\s*:\s*")[^"]*(")/,
        raw,
        fn _whole, prefix, suffix -> prefix <> new <> suffix end,
        global: false
      )

    if updated == raw do
      {:error, ~s(couldn't find the "version" field in manifest.json to bump)}
    else
      File.write!(path, updated)
      :ok
    end
  end

  defp bumped_manifest(manifest, nil), do: manifest
  defp bumped_manifest(manifest, %{to: new}), do: %{manifest | version: new}

  # ---- validation ----

  defp load(dir) do
    case Theme.load(dir) do
      {:ok, theme} -> {:ok, theme}
      {:error, reason} -> {:error, format_load_error(dir, reason)}
    end
  end

  defp format_load_error(dir, {:missing, _}),
    do: "No theme found in #{dir} (no manifest.json)."

  defp format_load_error(_dir, {:manifest, errors}),
    do: "manifest.json is invalid:\n" <> Enum.map_join(errors, "\n", &("  • " <> &1))

  defp format_load_error(_dir, {:templates, errors}),
    do:
      "Template problems — fix before packaging:\n" <>
        Enum.map_join(errors, "\n", fn {name, msg} -> "  • templates/#{name}.liquid: #{msg}" end)

  defp format_load_error(_dir, {:page_config, name, errors}),
    do:
      "templates/pages/#{name}.json is invalid:\n" <>
        Enum.map_join(errors, "\n", &("  • " <> &1))

  defp format_load_error(_dir, other), do: "Could not load theme: #{inspect(other)}"

  # ---- file collection ----

  defp collect(dir) do
    manifest = {"manifest.json", File.read!(Path.join(dir, "manifest.json"))}

    {css, css_warn} =
      if File.regular?(Path.join(dir, "theme.css")) do
        {[{"theme.css", File.read!(Path.join(dir, "theme.css"))}], []}
      else
        {[], ["theme.css is missing — the platform requires it"]}
      end

    # Every Liquid template (fixed + optional blog + pages/) plus the page
    # sidecar configs under templates/pages/. Theme.load already validated they
    # parse, so reading them here is safe.
    templates =
      Path.join([dir, "templates"])
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Enum.filter(&(Path.extname(&1) in [".liquid", ".json"]))
      |> Enum.sort()
      |> Enum.map(fn path -> {Path.relative_to(path, dir), File.read!(path)} end)

    {assets, skipped} = collect_assets(dir)

    {[manifest | css] ++ templates ++ assets, css_warn ++ skipped}
  end

  defp collect_assets(dir) do
    adir = Path.join(dir, "assets")

    if File.dir?(adir) do
      adir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce({[], []}, fn path, {entries, skipped} ->
        rel = Path.relative_to(path, dir)

        cond do
          match?({:ok, %{type: :symlink}}, File.lstat(path)) ->
            {entries, ["skipped #{rel} (symlink not allowed)" | skipped]}

          not File.regular?(path) ->
            {entries, skipped}

          String.downcase(Path.extname(path)) not in @asset_exts ->
            {entries, ["skipped #{rel} (disallowed file type)" | skipped]}

          true ->
            {[{rel, File.read!(path)} | entries], skipped}
        end
      end)
      |> then(fn {entries, skipped} -> {Enum.reverse(entries), Enum.reverse(skipped)} end)
    else
      {[], []}
    end
  end

  # ---- output path ----

  defp resolve_out(nil, manifest),
    do: {:ok, ensure_parent(Path.join(default_dir(), filename(manifest)))}

  defp resolve_out(out, manifest) do
    expanded = Path.expand(out)

    target =
      if String.ends_with?(expanded, ".zip") do
        expanded
      else
        # Anything else is treated as a directory to drop the zip into.
        Path.join(expanded, filename(manifest))
      end

    {:ok, ensure_parent(target)}
  end

  defp ensure_parent(path) do
    File.mkdir_p!(Path.dirname(path))
    path
  end

  defp default_dir do
    desktop = Path.join(System.user_home!(), "Desktop")
    if File.dir?(desktop), do: desktop, else: System.user_home!()
  end

  defp filename(manifest), do: "#{manifest.slug}-#{manifest.version}.zip"

  # ---- zip ----

  defp write_zip(path, entries) do
    specs = Enum.map(entries, fn {name, bin} -> {String.to_charlist(name), bin} end)

    case :zip.create(String.to_charlist(path), specs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "could not write zip: #{inspect(reason)}"}
    end
  end

  # ---- caps / warnings (non-fatal — the author may still want the file) ----

  defp cap_warnings(entries, path) do
    uncompressed = total_bytes(entries)
    count = length(entries)
    zip_bytes = File.stat!(path).size

    []
    |> warn_if(count > @max_files, "#{count} files exceeds the platform limit of #{@max_files}")
    |> warn_if(
      uncompressed > @max_uncompressed_bytes,
      "uncompressed size #{human(uncompressed)} exceeds the #{human(@max_uncompressed_bytes)} limit"
    )
    |> warn_if(
      zip_bytes > @max_zip_bytes,
      "zip size #{human(zip_bytes)} exceeds the #{human(@max_zip_bytes)} upload limit"
    )
  end

  defp slug_warnings(manifest) do
    if manifest.slug in @reserved_slugs do
      ["slug \"#{manifest.slug}\" is reserved — the platform will reject this upload"]
    else
      []
    end
  end

  defp warn_if(list, true, message), do: list ++ [message]
  defp warn_if(list, false, _message), do: list

  defp total_bytes(entries),
    do: Enum.reduce(entries, 0, fn {_n, bin}, acc -> acc + byte_size(bin) end)

  @doc "Human-readable byte size (e.g. \"41.2 KB\")."
  def human(bytes) when bytes < 1024, do: "#{bytes} B"

  def human(bytes) do
    units = ["KB", "MB", "GB"]

    {value, unit} =
      Enum.reduce_while(units, {bytes / 1024, "KB"}, fn unit, {v, _} ->
        if v < 1024, do: {:halt, {v, unit}}, else: {:cont, {v / 1024, unit}}
      end)

    "#{:erlang.float_to_binary(value, decimals: 1)} #{unit}"
  end
end
