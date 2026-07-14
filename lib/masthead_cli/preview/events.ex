defmodule MastheadCli.Preview.Events do
  @moduledoc """
  The preview's one-message pub/sub: the watcher publishes `:reload`, and every
  open `/__preview/events` stream (one per browser tab) receives it.

  A `Registry` in `:duplicate` mode is the whole implementation — no dep, and
  subscribers are unregistered automatically when their connection process dies.
  """

  @registry __MODULE__.Registry
  @topic :preview

  @doc "Child spec for the preview supervisor."
  def child_spec(_opts) do
    Registry.child_spec(keys: :duplicate, name: @registry)
  end

  @doc "Subscribe the calling process; it will receive `:reload` messages."
  def subscribe do
    {:ok, _} = Registry.register(@registry, @topic, [])
    :ok
  end

  @doc "Send `message` to every subscriber. A no-op when nothing is listening."
  def broadcast(message) do
    Registry.dispatch(@registry, @topic, fn subscribers ->
      for {pid, _} <- subscribers, do: send(pid, message)
    end)
  end
end
