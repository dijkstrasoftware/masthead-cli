defmodule MastheadCli.MixProject do
  use Mix.Project

  @version "0.3.0"

  def project do
    [
      app: :masthead_cli,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      escript: escript(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  defp escript do
    [
      main_module: MastheadCli.CLI,
      name: "masthead"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # The versions here mirror the host Masthead application (ledger) so the
  # preview renders byte-for-byte the way production does. Solid is the
  # Liquid engine; Earmark + html_sanitize_ex reproduce the content
  # pipeline; Bandit + Plug serve the local preview.
  defp deps do
    [
      {:solid, "~> 1.3"},
      {:earmark, "~> 1.4"},
      {:html_sanitize_ex, "~> 1.4"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:plug, "~> 1.16"}
    ]
  end
end
