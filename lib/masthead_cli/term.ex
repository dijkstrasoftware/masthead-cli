defmodule MastheadCli.Term do
  @moduledoc """
  Tiny terminal-styling helpers for the CLI's output.

  Colours are applied with ANSI escapes only when stdout is a real
  terminal, so redirected/piped output (logs, `> file`) stays clean.

  The brand accent is **masthead blue** (`#2563eb`), with `#1e40af` as the
  deeper variant — the same blues the masthead.site admin and landing UI
  use.
  """

  # 24-bit truecolor codes for the brand blues.
  @blue "38;2;37;99;235"
  @blue_deep "38;2;30;64;175"

  @doc "masthead blue."
  def blue(s), do: style(s, [@blue])

  @doc "masthead blue, bold."
  def blue_bold(s), do: style(s, ["1", @blue])

  @doc "Deep masthead blue, bold."
  def blue_deep(s), do: style(s, ["1", @blue_deep])

  def bold(s), do: style(s, ["1"])
  def dim(s), do: style(s, ["2"])

  @doc "Colour an HTTP status code by class (2xx green, 3xx cyan, 4xx yellow, 5xx red)."
  def status(code) when code in 200..299, do: style(to_string(code), ["32"])
  def status(code) when code in 300..399, do: style(to_string(code), ["36"])
  def status(code) when code in 400..499, do: style(to_string(code), ["33"])
  def status(code), do: style(to_string(code), ["31"])

  @doc "Wrap `s` in the given SGR codes, or return it unchanged when not a TTY."
  def style(s, codes) do
    if color?() do
      "\e[" <> Enum.join(codes, ";") <> "m" <> s <> "\e[0m"
    else
      s
    end
  end

  @doc "Clear the screen (and scrollback) when attached to a terminal; no-op otherwise."
  def clear do
    if color?(), do: IO.write("\e[2J\e[3J\e[H")
    :ok
  end

  @doc """
  True when stdout is an interactive terminal and colour isn't disabled.

  Uses `:prim_tty.isatty/1` (OTP 26+), which works under an escript's
  `-noshell` mode where `:io.columns/0` reports `:enotsup` even on a real
  TTY. Honours the `NO_COLOR` convention and `TERM=dumb`.
  """
  def color? do
    cond do
      (System.get_env("NO_COLOR") || "") != "" -> false
      System.get_env("TERM") == "dumb" -> false
      true -> isatty?()
    end
  end

  defp isatty? do
    :prim_tty.isatty(:stdout) == true
  rescue
    _ -> false
  catch
    _, _ -> false
  end
end
