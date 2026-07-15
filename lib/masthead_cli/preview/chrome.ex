defmodule MastheadCli.Preview.Chrome do
  @moduledoc """
  The preview editor shell: a page that holds the settings sidebar and renders
  the theme in an iframe beside it.

  The sidebar lives *outside* the theme's document on purpose. It never loses
  focus or scroll when the frame re-renders, the theme's CSS cannot bleed into
  it (nor its into the theme), and every edit can therefore be answered by a
  real server-side re-render rather than a CSS-variable poke.

  The CSS and JS are ordinary files under `priv/preview/`, read **at compile
  time** — an escript has no unpacked `priv/` to serve them from at runtime, so
  they are baked into the binary but still editable as real files.
  """

  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "preview", "chrome.css"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "preview", "chrome.js"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "preview", "frame.js"])

  @css File.read!(Path.join([__DIR__, "..", "..", "..", "priv", "preview", "chrome.css"]))
  @js File.read!(Path.join([__DIR__, "..", "..", "..", "priv", "preview", "chrome.js"]))
  @frame_js File.read!(Path.join([__DIR__, "..", "..", "..", "priv", "preview", "frame.js"]))

  @doc """
  The editor shell, framing `path` (the theme URL to show on open).
  """
  def page(path) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>masthead preview</title>
      <style>#{@css}</style>
    </head>
    <body data-path="#{escape_attr(path)}">
      <main class="mh-frame">
        <div class="mh-toolbar">
          <span class="mh-mark">masthead</span>
          <span class="mh-path" id="mh-path">#{escape(path)}</span>
          <a class="mh-open" id="mh-open" href="#{escape_attr(path)}" target="_blank" rel="noopener">Open raw &#8599;</a>
        </div>
        <iframe id="mh-view" name="mh-view" title="Theme preview" src="#{escape_attr(path)}"></iframe>
      </main>

      <aside class="mh-panel">
        <header class="mh-panel-head">
          <h1>Settings</h1>
          <button type="button" id="mh-reset" class="mh-reset" title="Discard every local edit">Reset</button>
        </header>
        <div class="mh-panel-body" id="mh-body"></div>
        <footer class="mh-panel-foot">
          <span id="mh-status" class="mh-status">Preview only &middot; saved to <code id="mh-file">preview.local.json</code></span>
        </footer>
      </aside>

      <script>#{@js}</script>
    </body>
    </html>
    """
  end

  @doc """
  The snippet spliced into every raw theme page. It keeps the theme's own HTML
  otherwise untouched:

    * viewed at the top level, it sends you to the editor shell for that path
      (so any URL — a link you followed, a bookmark — lands in the editor);
    * inside the frame, it reports its path to the shell (so the sidebar can
      follow along when you click through the theme's nav) and restores the
      scroll position across a re-render.
  """
  def frame_script, do: "<script>#{@frame_js}</script>"

  @doc "Splice the frame script in before the final `</body>` (append if absent)."
  def inject(html) do
    case String.split(html, "</body>") do
      [only] ->
        only <> frame_script()

      parts ->
        {leading, [last]} = Enum.split(parts, length(parts) - 1)
        Enum.join(leading, "</body>") <> frame_script() <> "</body>" <> last
    end
  end

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(text), do: text |> escape() |> String.replace("\"", "&quot;")
end
