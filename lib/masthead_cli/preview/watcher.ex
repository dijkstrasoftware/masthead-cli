defmodule MastheadCli.Preview.Watcher do
  @moduledoc """
  Watches the theme directory and tells connected browsers to reload.

  It polls mtimes rather than using an OS watcher: `file_system` ships a native
  listener in its `priv/` directory, and an escript has no `priv/` to unpack it
  from. A theme is a few dozen small files, so a scan every `@interval` costs
  nothing.

  The renderer already re-reads the theme on every request, so this only decides
  *when* the browser asks again. `preview.local.json` is deliberately not
  watched: the settings sidebar writes it and reloads the frame itself, and
  watching it would double every edit.
  """

  use GenServer

  alias MastheadCli.Preview.Events

  @interval 400

  @watched_files ~w(manifest.json theme.css preview.json)
  @watched_globs ["templates/**/*", "assets/**/*", "preview/**/*"]

  def start_link(opts) do
    dir = Keyword.fetch!(opts, :dir)
    GenServer.start_link(__MODULE__, dir, name: __MODULE__)
  end

  @impl true
  def init(dir) do
    schedule()
    {:ok, %{dir: dir, signature: signature(dir)}}
  end

  @impl true
  def handle_info(:poll, %{dir: dir, signature: previous} = state) do
    schedule()

    case signature(dir) do
      ^previous ->
        {:noreply, state}

      current ->
        Events.broadcast(:reload)
        {:noreply, %{state | signature: current}}
    end
  end

  defp schedule, do: Process.send_after(self(), :poll, @interval)

  # A theme's shape *and* its content: a renamed or deleted file changes the
  # path set, an edited one changes its mtime.
  defp signature(dir) do
    fixed = Enum.map(@watched_files, &Path.join(dir, &1))
    globbed = Enum.flat_map(@watched_globs, fn glob -> Path.wildcard(Path.join(dir, glob)) end)

    (fixed ++ globbed)
    |> Enum.sort()
    |> Enum.map(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %File.Stat{mtime: mtime, size: size}} -> {path, mtime, size}
        {:error, _} -> {path, :missing, 0}
      end
    end)
  end
end
