defmodule MastheadCli.InspectorTest do
  use ExUnit.Case, async: true

  alias MastheadCli.{FixtureTheme, Inspector, Manifest}

  setup do
    {dir, theme} = FixtureTheme.load!()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{manifest: theme.manifest}
  end

  describe "payload/2" do
    test "one entry per token with effective value and css var", %{manifest: m} do
      payload = Inspector.payload(m, %{})
      assert length(payload) == length(m.tokens)

      accent = Enum.find(payload, &(&1.key == "accent"))
      assert accent.value == "#0066cc"
      assert accent.css_var == "--accent"
      refute accent.file
    end

    test "kebab-cases underscores in the css var", %{manifest: m} do
      width = Enum.find(Inspector.payload(m, %{}), &(&1.key == "max_width"))
      assert width.css_var == "--max-width"
    end

    test "overrides win over defaults", %{manifest: m} do
      accent = Enum.find(Inspector.payload(m, %{"accent" => "#ff0000"}), &(&1.key == "accent"))
      assert accent.value == "#ff0000"
    end

    test "flags file tokens and defaults category to General", %{manifest: m} do
      logo = Enum.find(Inspector.payload(m, %{}), &(&1.key == "logo"))
      assert logo.file
      assert logo.category == "General"
    end
  end

  describe "inject/3" do
    test "splices the widget before the final </body>", %{manifest: m} do
      html = "<html><body><h1>hi</h1></body></html>"
      out = Inspector.inject(html, m, %{})

      assert out =~ "__mh_gear"
      assert out =~ ~s(id="__mh_inspector")
      # Inserted before the closing tag, document still well-formed-ish.
      assert out =~ "</body></html>"
      gear_pos = :binary.match(out, "__mh_gear") |> elem(0)
      body_close = :binary.match(out, "</body>") |> elem(0)
      assert gear_pos < body_close
    end

    test "embeds the token JSON payload", %{manifest: m} do
      out = Inspector.inject("<body></body>", m, %{"accent" => "#abcdef"})
      assert out =~ ~s(id="__mh_tokens")
      assert out =~ "--accent"
      assert out =~ "#abcdef"
    end

    test "escapes </ so the blob cannot break out of the script tag", %{manifest: _m} do
      {:ok, m} =
        Manifest.from_map(%{
          "name" => "X",
          "slug" => "x",
          "version" => "1.0.0",
          "tokens" => [
            %{"key" => "evil", "label" => "</script><b>x", "type" => "string", "default" => "v"}
          ]
        })

      out = Inspector.inject("<body></body>", m, %{})
      refute out =~ "</script><b>x"
      assert out =~ "<\\/script>"
    end

    test "appends when there is no </body>", %{manifest: m} do
      out = Inspector.inject("<div>no body tag</div>", m, %{})
      assert out =~ "<div>no body tag</div>"
      assert out =~ "__mh_gear"
    end

    test "returns html unchanged when the theme has no tokens" do
      {:ok, m} =
        Manifest.from_map(%{"name" => "X", "slug" => "x", "version" => "1.0.0", "tokens" => []})

      html = "<body>untouched</body>"
      assert Inspector.inject(html, m, %{}) == html
    end
  end
end
