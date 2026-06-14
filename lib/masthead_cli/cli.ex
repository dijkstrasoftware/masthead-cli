defmodule MastheadCli.CLI do
  @moduledoc """
  Command-line entrypoint for the `masthead` escript.

      masthead create NAME                       Scaffold a new theme
      masthead preview [--dir PATH] [--port N]   Serve a live preview
      masthead validate [--dir PATH]             Check a theme without serving
      masthead package [--dir PATH] [--out P]    Bundle the theme into a zip
      masthead doctor                            Check the runtime versions
      masthead version                           Print the version
      masthead help                              Show usage

  `preview` and `validate` default to the current working directory, so the
  common case is simply running `masthead preview` inside a theme folder.
  """

  @version Mix.Project.config()[:version]

  @runtime_apps [:solid, :earmark, :html_sanitize_ex, :jason, :plug, :bandit]

  def main(argv) do
    case argv do
      ["create" | rest] -> create(rest)
      ["preview" | rest] -> preview(rest)
      ["validate" | rest] -> validate(rest)
      ["package" | rest] -> package(rest)
      ["doctor" | _] -> doctor()
      ["version" | _] -> IO.puts("masthead #{@version}")
      ["--version" | _] -> IO.puts("masthead #{@version}")
      ["help" | _] -> IO.puts(usage())
      ["--help" | _] -> IO.puts(usage())
      ["-h" | _] -> IO.puts(usage())
      [] -> IO.puts(usage())
      [cmd | _] -> unknown(cmd)
    end
  end

  # ---- create ----

  # Clone the starter theme into a new directory. The positional NAME (or
  # --dir) is the directory to create; its basename seeds the slug, and a
  # title-cased version of that becomes the theme name.
  defp create(args) do
    {opts, rest} = parse(args)
    target = List.first(rest) || opts[:dir]

    if is_nil(target) do
      IO.puts(:stderr, "Usage: masthead create NAME    (e.g. masthead create my-theme)")
      System.halt(1)
    end

    dir = Path.expand(target)
    slug = MastheadCli.Scaffold.slugify(Path.basename(dir))

    if slug == "" do
      IO.puts(:stderr, "Could not derive a theme slug from #{inspect(Path.basename(dir))}.")
      IO.puts(:stderr, "Pick a name with lowercase letters or digits, e.g. masthead create my-theme.")
      System.halt(1)
    end

    name = MastheadCli.Scaffold.titleize(slug)

    case MastheadCli.Scaffold.create(dir, name, slug) do
      :ok ->
        print_create_success(dir, name, slug)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp print_create_success(dir, name, slug) do
    label = &MastheadCli.Term.dim/1
    rel = Path.relative_to_cwd(dir)

    IO.puts("""
    #{MastheadCli.Term.blue("✓")} #{MastheadCli.Term.blue_bold("created")} #{label.("#{name} (#{slug})")}

      #{MastheadCli.Term.blue("→")} #{dir}

    #{label.("Next:")}
      cd #{rel}
      masthead preview
    """)
  end

  # ---- preview ----

  defp preview(args) do
    {opts, _rest} = parse(args)
    dir = Path.expand(opts[:dir] || ".")
    port = opts[:port] || 4010
    inspector? = !opts[:no_inspector]

    # Start the preview on a clean screen.
    MastheadCli.Term.clear()

    ensure_runtime!()

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

    ensure_runtime!()

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

    ensure_runtime!()

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

  # ---- doctor ----

  # Reports the toolchain the escript was built with vs. the runtime it's
  # executing on, and flags an incompatible (older) Erlang/OTP.
  defp doctor do
    build = MastheadCli.Preflight.build_info()
    runtime = MastheadCli.Preflight.runtime_info()
    label = &MastheadCli.Term.dim/1

    IO.puts("""
    #{MastheadCli.Term.blue_bold("masthead")} #{label.("doctor")} #{label.("(v#{@version})")}

      #{label.("built with")}
        elixir   #{build.elixir}
        erlang   OTP #{build.otp} · ERTS #{build.erts}

      #{label.("running on")}
        elixir   #{runtime.elixir}
        erlang   OTP #{runtime.otp} · ERTS #{runtime.erts}
    """)

    case MastheadCli.Preflight.check() do
      :ok ->
        IO.puts("  #{MastheadCli.Term.blue("✓")} Erlang runtime is compatible with the build\n")

      {:error, message} ->
        IO.puts(
          MastheadCli.Term.style("  ✗ Erlang runtime is older than the build\n", ["1", "31"])
        )

        IO.puts(message)
        System.halt(1)
    end
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

  # Bail out with a clear message if the OTP runtime is older than the one
  # this escript was built against, then bring the bundled apps up.
  defp ensure_runtime! do
    case MastheadCli.Preflight.check() do
      :ok ->
        :ok

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end

    ensure_runtime_started()
  end

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
      masthead create NAME           Scaffold a new theme from the template
      masthead preview [options]     Serve a live preview of the theme
      masthead validate [options]    Validate the theme and exit
      masthead package [options]     Bundle the theme into an installable zip
      masthead doctor                Check the Erlang/Elixir runtime versions
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
      masthead create my-theme               # scaffold a new theme directory
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
