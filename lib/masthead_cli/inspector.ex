defmodule MastheadCli.Inspector do
  @moduledoc """
  The live token inspector — a dev-only overlay the preview server injects
  into the theme's rendered HTML.

  This is the deliberately-sketchy part of `masthead_cli`: production never
  touches a theme's output, but in preview we splice a floating gear button
  and a token sidebar in just before `</body>`. Editing a control rewrites
  the matching CSS custom property on `documentElement` live —

      document.documentElement.style.setProperty("--accent", "#ff0000")

  — and because an inline style on `:root` wins over the theme's
  `<style> :root { … } </style>` block, the change is instant with no
  re-render.

  Edits are **ephemeral**: nothing is written to disk, and a refresh resets
  to the manifest / `preview.json` values. Only tokens consumed as CSS
  variables update live; tokens used in template logic (e.g. an email in a
  `mailto:`) are baked into the HTML at render time — the panel says so.
  """

  alias MastheadCli.Manifest

  @doc """
  Build the inspector's seed data: one entry per manifest token, carrying
  the schema plus the current effective value and the CSS variable it maps
  to. `css_var` uses the same `_ -> -` kebab rule as
  `Renderer.declaration/3`.
  """
  def payload(%Manifest{tokens: tokens} = manifest, site_tokens) do
    effective = Manifest.effective_tokens(manifest, site_tokens || %{})

    Enum.map(tokens, fn t ->
      %{
        key: t.key,
        label: t.label,
        type: t.type,
        default: t.default,
        options: t.options,
        category: t.category || "General",
        value: Map.get(effective, t.key, t.default),
        css_var: "--" <> String.replace(t.key, "_", "-"),
        file: t.type == "file"
      }
    end)
  end

  @doc """
  Inject the inspector widget into a rendered HTML document, seeded from the
  theme's tokens. Splices in before the final `</body>` (appends if the tag
  is absent). With no tokens, the HTML is returned unchanged.
  """
  def inject(html, %Manifest{} = manifest, site_tokens) do
    case payload(manifest, site_tokens) do
      [] -> html
      tokens -> splice(html, widget(tokens))
    end
  end

  # ---- injection ----

  defp splice(html, widget) do
    case String.split(html, "</body>") do
      [only] ->
        only <> widget

      parts ->
        {leading, [last]} = Enum.split(parts, length(parts) - 1)
        Enum.join(leading, "</body>") <> widget <> "</body>" <> last
    end
  end

  # ---- markup ----

  defp widget(tokens) do
    json =
      tokens
      |> Jason.encode!()
      # Keep the blob from breaking out of the <script> element.
      |> String.replace("</", "<\\/")

    """
    <script type="application/json" id="__mh_tokens">#{json}</script>
    <style>#{styles()}</style>
    <button id="__mh_gear" type="button" aria-label="Toggle token inspector" title="Tokens (` or Cmd/Ctrl+E)">
      #{gear_svg()}
    </button>
    <aside id="__mh_inspector" aria-hidden="true">
      <header>
        <span class="__mh-title">Theme tokens</span>
        <button type="button" class="__mh-close" aria-label="Close">&times;</button>
      </header>
      <div class="__mh-body"></div>
      <footer>
        <button type="button" class="__mh-reset">Reset</button>
        <span class="__mh-note">Live preview · not saved · refresh to reset</span>
      </footer>
    </aside>
    <script>#{script()}</script>
    """
  end

  defp gear_svg do
    """
    <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="3"></circle>
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"></path>
    </svg>
    """
  end

  # ---- styles (all scoped under our two ids; explicit reset so theme CSS
  # can't bleed in and ours can't leak out) ----

  defp styles do
    """
    #__mh_gear, #__mh_inspector, #__mh_inspector * {
      all: revert;
      box-sizing: border-box;
      font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    }
    #__mh_gear {
      position: fixed; right: 20px; bottom: 20px; z-index: 2147483000;
      width: 46px; height: 46px; border-radius: 50%; border: none; cursor: pointer;
      display: flex; align-items: center; justify-content: center;
      background: #111827; color: #f9fafb;
      box-shadow: 0 6px 20px rgba(0,0,0,.32); transition: transform .15s ease, background .15s ease;
    }
    #__mh_gear:hover { background: #1f2937; transform: rotate(25deg); }
    #__mh_inspector {
      position: fixed; top: 0; right: 0; z-index: 2147483000;
      width: 340px; max-width: 92vw; height: 100vh;
      background: #0f1115; color: #e5e7eb;
      border-left: 1px solid #262b36; box-shadow: -12px 0 32px rgba(0,0,0,.4);
      display: flex; flex-direction: column;
      transform: translateX(100%); transition: transform .2s ease; pointer-events: none;
      font-size: 13px; line-height: 1.5;
    }
    #__mh_inspector.__mh-open { transform: translateX(0); pointer-events: auto; }
    #__mh_inspector header {
      display: flex; align-items: center; justify-content: space-between;
      padding: 14px 16px; border-bottom: 1px solid #262b36; flex: 0 0 auto;
    }
    #__mh_inspector .__mh-title { font-weight: 600; font-size: 13px; letter-spacing: .01em; }
    #__mh_inspector .__mh-close {
      background: none; border: none; color: #9ca3af; font-size: 22px; line-height: 1;
      cursor: pointer; padding: 0 4px;
    }
    #__mh_inspector .__mh-close:hover { color: #f9fafb; }
    #__mh_inspector .__mh-body { flex: 1 1 auto; overflow-y: auto; padding: 8px 16px 16px; }
    #__mh_inspector .__mh-cat {
      margin: 16px 0 8px; font-size: 11px; text-transform: uppercase; letter-spacing: .08em;
      color: #6b7280;
    }
    #__mh_inspector .__mh-row { margin: 12px 0; }
    #__mh_inspector .__mh-row label {
      display: flex; align-items: baseline; gap: 6px; margin-bottom: 5px; color: #d1d5db;
    }
    #__mh_inspector .__mh-row label code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11px; color: #6b7280;
    }
    #__mh_inspector input[type="text"], #__mh_inspector select {
      width: 100%; background: #1a1d24; border: 1px solid #2d333f; border-radius: 7px;
      color: #f3f4f6; padding: 7px 9px; font-size: 13px;
    }
    #__mh_inspector input[type="text"]:focus, #__mh_inspector select:focus {
      outline: none; border-color: #6366f1;
    }
    #__mh_inspector .__mh-color { display: flex; gap: 8px; align-items: center; }
    #__mh_inspector .__mh-color input[type="color"] {
      width: 38px; height: 34px; padding: 0; border: 1px solid #2d333f; border-radius: 7px;
      background: #1a1d24; cursor: pointer; flex: 0 0 auto;
    }
    #__mh_inspector .__mh-color input[type="text"] { flex: 1 1 auto; }
    #__mh_inspector footer {
      flex: 0 0 auto; padding: 12px 16px; border-top: 1px solid #262b36;
      display: flex; align-items: center; gap: 12px;
    }
    #__mh_inspector .__mh-reset {
      background: #1f2430; border: 1px solid #2d333f; border-radius: 7px; color: #e5e7eb;
      padding: 7px 14px; cursor: pointer; font-size: 12px;
    }
    #__mh_inspector .__mh-reset:hover { background: #272d3a; }
    #__mh_inspector .__mh-note { color: #6b7280; font-size: 11px; }
    """
  end

  # ---- behaviour (vanilla IIFE; reads the JSON blob, builds rows, wires
  # live CSS-variable updates and the toggle shortcuts) ----

  defp script do
    """
    (function () {
      var el = document.getElementById("__mh_tokens");
      if (!el) return;
      var tokens;
      try { tokens = JSON.parse(el.textContent); } catch (e) { return; }

      var panel = document.getElementById("__mh_inspector");
      var gear = document.getElementById("__mh_gear");
      var body = panel.querySelector(".__mh-body");
      var root = document.documentElement;
      var hexRe = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;

      function apply(tok, val) {
        if (tok.file) {
          if (val) root.style.setProperty(tok.css_var, "url(" + val + ")");
          else root.style.removeProperty(tok.css_var);
        } else {
          root.style.setProperty(tok.css_var, val);
        }
      }

      function clear(tok) { root.style.removeProperty(tok.css_var); }

      function rowLabel(tok) {
        var label = document.createElement("label");
        label.appendChild(document.createTextNode(tok.label || tok.key));
        var code = document.createElement("code");
        code.textContent = tok.key;
        label.appendChild(code);
        return label;
      }

      var controls = [];

      function buildControl(tok) {
        var setVal, getVal, focusables = [];

        if (tok.type === "color") {
          var wrap = document.createElement("div");
          wrap.className = "__mh-color";
          var color = document.createElement("input");
          color.type = "color";
          var text = document.createElement("input");
          text.type = "text";
          wrap.appendChild(color);
          wrap.appendChild(text);
          focusables = [text];
          setVal = function (v) {
            text.value = v || "";
            if (hexRe.test(v)) color.value = v;
          };
          getVal = function () { return text.value; };
          color.addEventListener("input", function () { text.value = color.value; apply(tok, color.value); });
          text.addEventListener("input", function () {
            if (hexRe.test(text.value)) color.value = text.value;
            apply(tok, text.value);
          });
          tok._el = wrap;
        } else if (tok.type === "select") {
          var select = document.createElement("select");
          (tok.options || []).forEach(function (opt) {
            var o = document.createElement("option");
            o.value = opt; o.textContent = opt;
            select.appendChild(o);
          });
          focusables = [select];
          setVal = function (v) { select.value = v; };
          getVal = function () { return select.value; };
          select.addEventListener("change", function () { apply(tok, select.value); });
          tok._el = select;
        } else {
          var input = document.createElement("input");
          input.type = "text";
          if (tok.type === "number") input.inputMode = "decimal";
          if (tok.file) input.placeholder = "URL or /assets/… path";
          focusables = [input];
          setVal = function (v) { input.value = v || ""; };
          getVal = function () { return input.value; };
          input.addEventListener("input", function () { apply(tok, input.value); });
          tok._el = input;
        }

        setVal(tok.value);
        controls.push({ tok: tok, setVal: setVal, getVal: getVal });
        focusables.forEach(function (f) { f.setAttribute("data-mh-input", "1"); });
        return tok._el;
      }

      // Build rows grouped by category, preserving first-seen order.
      var seen = {}, order = [];
      tokens.forEach(function (t) { if (!seen[t.category]) { seen[t.category] = []; order.push(t.category); } seen[t.category].push(t); });
      order.forEach(function (cat) {
        var h = document.createElement("div");
        h.className = "__mh-cat";
        h.textContent = cat;
        body.appendChild(h);
        seen[cat].forEach(function (tok) {
          var row = document.createElement("div");
          row.className = "__mh-row";
          row.appendChild(rowLabel(tok));
          row.appendChild(buildControl(tok));
          body.appendChild(row);
        });
      });

      function open() { panel.classList.add("__mh-open"); panel.setAttribute("aria-hidden", "false"); }
      function close() { panel.classList.remove("__mh-open"); panel.setAttribute("aria-hidden", "true"); }
      function toggle() { panel.classList.contains("__mh-open") ? close() : open(); }

      gear.addEventListener("click", toggle);
      panel.querySelector(".__mh-close").addEventListener("click", close);
      panel.querySelector(".__mh-reset").addEventListener("click", function () {
        controls.forEach(function (c) { c.setVal(c.tok.value); clear(c.tok); });
      });

      function typingInPanel() {
        var a = document.activeElement;
        return a && (a.getAttribute("data-mh-input") === "1");
      }

      document.addEventListener("keydown", function (e) {
        // Cmd/Ctrl+E — always toggles.
        if ((e.metaKey || e.ctrlKey) && (e.key === "e" || e.key === "E")) {
          e.preventDefault();
          toggle();
          return;
        }
        // Backtick — toggles, unless you're typing in one of our fields.
        if (e.key === "`" && !e.metaKey && !e.ctrlKey && !e.altKey && !typingInPanel()) {
          e.preventDefault();
          toggle();
        }
      });
    })();
    """
  end
end
