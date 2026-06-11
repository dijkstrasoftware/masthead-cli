defmodule MastheadCli.CLI do
  @moduledoc """
  Command-line entrypoint for the `masthead` escript.

      masthead preview [--dir PATH] [--port N]   Serve a live preview
      masthead validate [--dir PATH]             Check a theme without serving
      masthead package [--dir PATH] [--out P]    Bundle the theme into a zip
      masthead version                           Print the version
      masthead help                              Show usage

  `preview` and `validate` default to the current working directory, so the
  common case is simply running `masthead preview` inside a theme folder.
  """

  @version Mix.Project.config()[:version]

  @runtime_apps [:solid, :earmark, :html_sanitize_ex, :jason, :plug, :bandit]

  def main(argv) do
    case argv do
      ["preview" | rest] -> preview(rest)
      ["validate" | rest] -> validate(rest)
      ["package" | rest] -> package(rest)
      ["version" | _] -> IO.puts("masthead #{@version}")
      ["--version" | _] -> IO.puts("masthead #{@version}")
      ["help" | _] -> IO.puts(usage())
      ["--help" | _] -> IO.puts(usage())
      ["-h" | _] -> IO.puts(usage())
      [] -> IO.puts(usage())
      [cmd | _] -> unknown(cmd)
    end
  end

  # ---- preview ----

  defp preview(args) do
    {opts, _rest} = parse(args)
    dir = Path.expand(opts[:dir] || ".")
    port = opts[:port] || 4010
    inspector? = !opts[:no_inspector]

    # Start the preview on a clean screen.
    MastheadCli.Term.clear()

    ensure_runtime_started()

    # A missing manifest almost always means "wrong directory" — bail with a
    # clear message. Manifest/template *errors*, by contrast, are exactly
    # what the author is iterating on: start anyway and surface them in the
    # browser so live-reload lets them fix-and-refresh without restarting.
    case MastheadCli.Theme.load(dir) do
      {:error, {:missing, _} = reason} ->
        IO.puts(:stderr, format_load_error(dir, reason))
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Warning — the theme has problems (shown in the browser too):\n")
        IO.puts(:stderr, format_load_error(dir, reason) <> "\n")
        start_server(dir, port, inspector?)

      {:ok, _theme} ->
        start_server(dir, port, inspector?)
    end
  end

  defp start_server(dir, port, inspector?) do
    print_banner(dir, port, inspector?)

    case MastheadCli.Server.serve(dir, port, inspector?) do
      {:error, reason} ->
        IO.puts(:stderr, "\nCould not start the server on port #{port}: #{inspect(reason)}")
        IO.puts(:stderr, "Is something already listening there? Try --port <other>.")
        System.halt(1)

      _ ->
        :ok
    end
  end

  defp print_banner(dir, port, inspector?) do
    bar = MastheadCli.Term.blue("▌")
    label = &MastheadCli.Term.dim/1

    lines =
      [
        "",
        "#{bar} #{MastheadCli.Term.blue_bold("masthead")} #{label.("preview")}",
        "#{bar} #{label.("theme:")}  #{dir}",
        "#{bar} #{label.("url:")}    #{MastheadCli.Term.blue("http://localhost:#{port}")}",
        "#{bar}",
        "#{bar} #{label.("Templates, CSS, manifest and preview content reload on every request.")}"
      ] ++
        if inspector? do
          ["#{bar} #{label.("Live token inspector:")} click the gear, or press ` / Cmd+Ctrl+E."]
        else
          []
        end ++
        [
          "#{bar} #{label.("Press Ctrl+C twice to stop.")}",
          ""
        ]

    IO.puts(Enum.join(lines, "\n"))
    IO.puts(MastheadCli.Term.dim("  requests"))
  end

  # ---- validate ----

  defp validate(args) do
    {opts, _rest} = parse(args)
    dir = Path.expand(opts[:dir] || ".")

    ensure_runtime_started()

    case validate_theme(dir, quiet: false) do
      :ok ->
        :ok

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  # Loads the theme and reports. With quiet: false, prints a success summary.
  defp validate_theme(dir, opts) do
    quiet = Keyword.get(opts, :quiet, true)

    case MastheadCli.Theme.load(dir) do
      {:ok, theme} ->
        unless quiet, do: print_validate_success(theme)
        :ok

      {:error, reason} ->
        {:error, format_load_error(dir, reason)}
    end
  end

  defp print_validate_success(theme) do
    m = theme.manifest
    label = &MastheadCli.Term.dim/1

    IO.puts("""
    #{MastheadCli.Term.blue("✓")} #{MastheadCli.Term.blue_bold(m.name)} #{label.("(#{m.slug}) v#{m.version}")}

      #{label.("manifest")}   ok
      #{label.("templates")}  ok (#{map_size(theme.templates)} parsed)
      #{label.("css")}        #{byte_size(theme.css)} bytes
      #{label.("tokens")}     #{length(m.tokens)} declared
      #{label.("metadata")}   #{length(m.metadata)} field(s)
    """)
  end

  # ---- package ----

  defp package(args) do
    {opts, rest} = parse(args)
    dir = Path.expand(opts[:dir] || ".")
    # The output path may be given as --out/-o or as a bare positional arg.
    out = opts[:out] || List.first(rest)

    ensure_runtime_started()

    case MastheadCli.Packager.package(dir, out, opts[:bump]) do
      {:ok, summary} ->
        print_package_success(summary)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp print_package_success(summary) do
    label = &MastheadCli.Term.dim/1

    size =
      "#{MastheadCli.Packager.human(summary.zip_bytes)} zip · #{MastheadCli.Packager.human(summary.uncompressed)} unpacked"

    header =
      "#{MastheadCli.Term.blue("✓")} #{MastheadCli.Term.blue_bold("packaged")} #{label.("#{summary.slug} v#{summary.version}")}"

    bump_lines =
      case summary.bump do
        nil ->
          []

        %{from: from, to: to, level: level} ->
          ["  #{MastheadCli.Term.blue("↑")} #{label.("bumped #{from} → #{to} (#{level})")}"]
      end

    lines =
      [header, ""] ++
        bump_lines ++
        [
          "  #{MastheadCli.Term.blue("→")} #{summary.path}",
          "  #{label.("#{summary.file_count} files · #{size}")}",
          ""
        ]

    IO.puts(Enum.join(lines, "\n"))

    Enum.each(summary.warnings, fn w ->
      IO.puts(MastheadCli.Term.style("  ! #{w}", ["33"]))
    end)
  end

  # ---- shared ----

  defp format_load_error(dir, {:missing, _message}) do
    "No theme found in #{dir} (no manifest.json).\n" <>
      "Run this inside a theme directory, or pass --dir PATH."
  end

  defp format_load_error(_dir, {:manifest, errors}) do
    "manifest.json is invalid:\n" <> Enum.map_join(errors, "\n", &("  • " <> &1))
  end

  defp format_load_error(_dir, {:templates, errors}) do
    "Template problems:\n" <>
      Enum.map_join(errors, "\n", fn {name, msg} -> "  • templates/#{name}.liquid: #{msg}" end)
  end

  defp format_load_error(_dir, other), do: "Could not load theme: #{inspect(other)}"

  # Accepted --bump levels (matches MastheadCli.Packager).
  @bump_levels ~w(major minor bugfix patch)

  defp parse(args) do
    {opts, rest, _invalid} =
      args
      |> normalize_bump()
      |> OptionParser.parse(
        strict: [
          dir: :string,
          port: :integer,
          no_inspector: :boolean,
          out: :string,
          bump: :string
        ],
        aliases: [d: :dir, p: :port, o: :out]
      )

    {opts, rest}
  end

  # `--bump` takes an optional value. A bare `--bump` (or one followed by a
  # non-level token, e.g. a positional output path) defaults to "bugfix";
  # `--bump minor` / `--bump major` pass the level through.
  defp normalize_bump([]), do: []

  defp normalize_bump(["--bump", value | rest]) when value in @bump_levels,
    do: ["--bump=" <> value | normalize_bump(rest)]

  defp normalize_bump(["--bump" | rest]), do: ["--bump=bugfix" | normalize_bump(rest)]
  defp normalize_bump([arg | rest]), do: [arg | normalize_bump(rest)]

  defp ensure_runtime_started do
    Enum.each(@runtime_apps, fn app ->
      case Application.ensure_all_started(app) do
        {:ok, _} -> :ok
        # Pure libraries with no .app entry point are fine to skip.
        {:error, _} -> :ok
      end
    end)
  end

  defp unknown(cmd) do
    IO.puts(:stderr, "Unknown command: #{cmd}\n")
    IO.puts(:stderr, usage())
    System.halt(1)
  end

  defp usage do
    """
    masthead #{@version} — local preview for Masthead themes

    USAGE
      masthead preview [options]     Serve a live preview of the theme
      masthead validate [options]    Validate the theme and exit
      masthead package [options]     Bundle the theme into an installable zip
      masthead version               Print the version
      masthead help                  Show this help

    OPTIONS
      -d, --dir PATH    Theme directory (default: current directory)
      -p, --port N      Port for `preview` (default: 4010)
      --no-inspector    Disable the live token inspector overlay
      -o, --out PATH    Output for `package`: a .zip file path or a directory
                        (default: ~/Desktop/<slug>-<version>.zip)
      --bump [LEVEL]    Bump manifest.json's version before packaging:
                        major | minor | bugfix (bare --bump = bugfix)

    EXAMPLES
      cd my-theme && masthead preview
      masthead preview --dir ~/themes/acme --port 4020
      masthead validate
      masthead package                       # -> ~/Desktop/<slug>-<version>.zip
      masthead package --out ~/Downloads     # into a directory
      masthead package -o ./dist/theme.zip   # exact file path
      masthead package --bump                # bump patch, then package
      masthead package --bump minor          # bump minor, then package
    """
  end
end
