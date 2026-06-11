defmodule MastheadCli.Content do
  @moduledoc """
  Render a post or page body to safe HTML — faithful copy of the host's
  `Masthead.Content.render_body/2` plus `Masthead.Content.HTML`.

  Dispatches on `format`:

    * `"markdown"` — parse with Earmark (HTML in source is escaped), then
      run through the sanitizer as defense in depth.
    * `"html"` — sanitize the raw input directly.
  """

  alias MastheadCli.Content.Scrubber

  @doc "Render a post/page body to safe HTML. Always returns a string."
  def render_body(nil, _format), do: ""
  def render_body(body, "html") when is_binary(body), do: sanitize(body)

  def render_body(body, _markdown) when is_binary(body) do
    case Earmark.as_html(body, escape: true, code_class_prefix: "lang-") do
      {:ok, html, _} -> sanitize(html)
      {:error, html, _} -> sanitize(html)
    end
  end

  @doc "Sanitize a binary of HTML. Always returns a binary."
  def sanitize(nil), do: ""
  def sanitize(html) when is_binary(html), do: Scrubber.sanitize(html)
end
