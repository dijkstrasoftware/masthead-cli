defmodule MastheadCli.Server do
  @moduledoc """
  Starts the preview: a Bandit listener bound to localhost, the file watcher that
  tells open browsers to reload, and the pub/sub registry between them. Then it
  blocks the calling (escript) process so the VM stays alive.
  """

  alias MastheadCli.Preview.{Events, Watcher}
  alias MastheadCli.Router

  @doc """
  Serve `dir` on `port` (localhost only) and block forever.

  `editor?` toggles the settings sidebar: with it off, the theme is served bare
  at the production routes and nothing at all is injected into its HTML.

  Returns `{:error, reason}` if the listener can't bind (e.g. the port is already
  taken); otherwise it never returns.
  """
  def serve(dir, port, editor? \\ true) do
    case Supervisor.start_link(children(dir, port, editor?), strategy: :one_for_one) do
      {:ok, _pid} ->
        Process.sleep(:infinity)

      {:error, {:shutdown, {:failed_to_start_child, _child, reason}}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp children(dir, port, editor?) do
    listener =
      {Bandit,
       plug: {Router, dir: dir, editor: editor?},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: port,
       startup_log: false}

    # The watcher exists only to push reloads to the editor; with the editor off,
    # nothing is listening for them.
    if editor? do
      [Events, {Watcher, dir: dir}, listener]
    else
      [listener]
    end
  end
end
