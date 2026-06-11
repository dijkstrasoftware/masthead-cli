defmodule MastheadCli.Sandbox do
  @moduledoc """
  Thin wrapper around `Solid` pinned to the same safe configuration the
  host Masthead application uses for user-uploaded themes:

    * No file system — `{% include %}` / `{% render %}` partials are
      disabled. A template using them fails to parse with a clear error.
    * Custom filter allowlist via `MastheadCli.Filters`. Solid's standard
      filters (`escape`, `default`, `date`, ...) remain available.
    * Solid (and Liquid) **does not auto-escape**. Theme authors are
      expected to call `| escape` on user-supplied strings. `body_html`
      is intentionally raw (it has already been sanitized).
  """

  alias Solid.Template

  @spec parse(String.t()) :: {:ok, Template.t()} | {:error, term()}
  def parse(source) when is_binary(source) do
    case Solid.parse(source) do
      {:ok, template} -> {:ok, template}
      {:error, %Solid.TemplateError{} = err} -> {:error, err}
      other -> {:error, other}
    end
  end

  @spec render(Template.t(), map()) :: {:ok, iodata(), list()} | {:error, term()}
  def render(%Template{} = template, context) when is_map(context) do
    Solid.render(template, context, custom_filters: MastheadCli.Filters)
  end

  @spec render_string(String.t(), map()) :: {:ok, iodata()} | {:error, term()}
  def render_string(source, context) do
    with {:ok, template} <- parse(source),
         {:ok, out, _errs} <- render(template, context) do
      {:ok, out}
    end
  end
end
