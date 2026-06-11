defmodule MastheadCli.CssSanitizer do
  @moduledoc """
  Last-line-of-defense scrubber for CSS, faithful copy of
  `Masthead.Themes.CssSanitizer`. Applied to two user-controllable
  surfaces:

    * site CSS overrides — free-text CSS appended to the theme's
      stylesheet on every render.
    * token values — spliced into a `:root { --foo: <value> }` block.
  """

  @doc "Sanitize a CSS overrides blob. Empty / nil -> empty string."
  @spec sanitize_overrides(String.t() | nil) :: String.t()
  def sanitize_overrides(nil), do: ""
  def sanitize_overrides(""), do: ""

  def sanitize_overrides(css) when is_binary(css) do
    Enum.reduce(bad_css_patterns(), css, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  defp bad_css_patterns do
    [
      {~r/@import\s+[^;]+;?/i, ""},
      {~r/expression\s*\(/i, "/* expression( */"},
      {~r/url\s*\(\s*['"]?\s*javascript:/i, "url("},
      {~r{</\s*style\s*>}i, ""},
      {~r/<\s*script/i, ""}
    ]
  end

  @doc """
  Sanitize a single token value. Strips characters that would let a
  malicious token break out of `--key: <value>;`.
  """
  @spec sanitize_token_value(String.t() | nil) :: String.t()
  def sanitize_token_value(nil), do: ""

  def sanitize_token_value(value) when is_binary(value) do
    value
    |> String.replace(~r/[{}<>;"\r\n]/, "")
    |> String.trim()
  end

  def sanitize_token_value(other), do: sanitize_token_value(to_string(other))
end
