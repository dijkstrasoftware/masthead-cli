defmodule MastheadCli.Server do
  @moduledoc """
  Starts a Bandit HTTP server bound to localhost that serves the preview
  router, then blocks the calling (escript) process so the VM stays alive.
  """

  alias MastheadCli.Router

  @doc """
  Start serving `dir` on `port` (localhost only) and block forever.

  `inspector?` toggles the dev-only live token inspector overlay.

  Returns `{:error, reason}` if the listener can't bind (e.g. the port is
  already in use); otherwise it never returns.
  """
  def serve(dir, port, inspector? \\ true) do
    case start_listener(dir, port, inspector?) do
      {:ok, _pid} ->
        Process.sleep(:infinity)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_listener(dir, port, inspector?) do
    Bandit.start_link(
      plug: {Router, dir: dir, inspector: inspector?},
      scheme: :http,
      ip: {127, 0, 0, 1},
      port: port,
      startup_log: false
    )
  end
end
