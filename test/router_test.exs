defmodule MastheadCli.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MastheadCli.{FixtureTheme, Router}
  alias MastheadCli.Preview.Settings

  # A theme whose *tokens* include an `object` and a `list` — the platform's
  # field types are the same for tokens and page metadata — plus a theme page
  # whose sidecar config declares the same containers.
  @manifest """
  {
    "name": "Router Theme",
    "slug": "router-theme",
    "version": "1.0.0",
    "tokens": [
      {"key": "accent", "label": "Accent", "type": "color", "default": "#0066cc"},
      {"key": "hero", "label": "Hero", "type": "object", "fields": [
        {"key": "title", "label": "Title", "type": "string", "default": "Default hero"}
      ]},
      {"key": "links", "label": "Links", "type": "list", "item_label": "Link",
       "default": [{"label": "Home"}],
       "fields": [
         {"key": "label", "label": "Label", "type": "string", "default": ""},
         {"key": "url", "label": "URL", "type": "url", "default": "/"}
       ]}
    ],
    "metadata": []
  }
  """

  # The layout surfaces the container tokens, so every route can assert on them.
  @layout """
  <!DOCTYPE html>
  <html>
  <head><style>{{ theme.css }}</style></head>
  <body data-hero="{{ theme.tokens.hero.title }}">
  <ul class="links">{% for link in theme.tokens.links %}<li>{{ link.label }}|{{ link.url }}</li>{% endfor %}</ul>
  <main>{{ content }}</main>
  </body>
  </html>
  """

  @home_page """
  <section data-title="{{ page.metadata.hero.title }}">
  {% for member in page.metadata.crew %}<span>{{ member.name }}</span>{% endfor %}
  </section>
  """

  @home_config """
  {
    "label": "Homepage",
    "metadata": [
      {"key": "hero", "label": "Hero", "type": "object", "fields": [
        {"key": "title", "label": "Title", "type": "string", "default": "Page hero"}
      ]},
      {"key": "crew", "label": "Crew", "type": "list", "item_label": "Member", "default": [],
       "fields": [{"key": "name", "label": "Name", "type": "string", "default": ""}]}
    ]
  }
  """

  @preview_json """
  {
    "site": {"name": "Router Site", "homepage": "home"},
    "pages": [
      {"title": "Home", "slug": "home", "format": "theme", "template": "home"},
      {"title": "About", "slug": "about", "format": "markdown", "body": "About body."}
    ],
    "posts": [
      {"title": "Hello", "slug": "hello", "body": "Post body.", "tags": ["Elixir"]}
    ]
  }
  """

  setup do
    dir =
      FixtureTheme.create!(%{
        "manifest.json" => @manifest,
        "templates/layout.liquid" => @layout,
        "templates/pages/home.liquid" => @home_page,
        "templates/pages/home.json" => @home_config,
        "preview.json" => @preview_json,
        "assets/logo.png" => "not-really-a-png"
      })

    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  defp request(dir, method, path, body \\ nil) do
    conn =
      case body do
        nil ->
          conn(method, path)

        payload ->
          method
          |> conn(path, Jason.encode!(payload))
          |> put_req_header("content-type", "application/json")
      end

    Router.call(conn, Router.init(dir: dir, log: false))
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  describe "the theme routes" do
    test "the homepage renders the site's designated theme page", %{dir: dir} do
      conn = request(dir, :get, "/")

      assert conn.status == 200
      # Its defaults come from the sidecar config, not the manifest's metadata.
      assert conn.resp_body =~ ~s(data-title="Page hero")
    end

    test "a post, a page, and an unknown slug (the themed 404)", %{dir: dir} do
      assert request(dir, :get, "/posts/hello").status == 200
      assert request(dir, :get, "/about").resp_body =~ "About body."

      missing = request(dir, :get, "/nope")
      assert missing.status == 404
      assert missing.resp_body =~ "Not found"
    end

    test "assets are served from the theme's assets/ folder", %{dir: dir} do
      assert request(dir, :get, "/assets/logo.png").status == 200
      assert request(dir, :get, "/assets/missing.png").status == 404
    end

    test "the frame script is injected, so a raw URL lands in the editor", %{dir: dir} do
      assert request(dir, :get, "/about").resp_body =~ "/__preview?path="
    end

    test "--no-editor serves the theme's HTML untouched", %{dir: dir} do
      conn = Router.call(conn(:get, "/about"), Router.init(dir: dir, editor: false, log: false))

      refute conn.resp_body =~ "__preview"
    end
  end

  describe "object/list tokens" do
    test "their defaults reach the template, and containers stay out of the CSS", %{dir: dir} do
      body = request(dir, :get, "/about").resp_body

      assert body =~ ~s(data-hero="Default hero")
      # The list's declared default item, filled out against the nested schema.
      assert body =~ "<li>Home|/</li>"

      # A scalar token becomes a custom property; a map or a list has no CSS
      # form, so it never reaches the `:root` block.
      assert body =~ "--accent: #0066cc;"
      refute body =~ "--hero"
      refute body =~ "--links"
    end
  end

  describe "the editor" do
    test "/__preview serves the shell framing the requested path", %{dir: dir} do
      conn = request(dir, :get, "/__preview?path=/about")

      assert conn.status == 200
      assert conn.resp_body =~ ~s(<iframe id="mh-view")
      assert conn.resp_body =~ ~s(src="/about")
    end

    test "/__preview/state carries the token schema and the framed page's schema", %{dir: dir} do
      state = dir |> request(:get, "/__preview/state?path=/") |> json()

      assert %{"tokens" => tokens, "page" => page, "routes" => routes, "assets" => assets} = state

      assert Enum.map(tokens["fields"], & &1["type"]) == ["color", "object", "list"]
      assert tokens["values"]["hero"] == %{"title" => "Default hero"}
      assert tokens["values"]["links"] == [%{"label" => "Home", "url" => "/"}]

      assert page["slug"] == "home"
      assert page["label"] == "Homepage"
      assert Enum.map(page["fields"], & &1["key"]) == ["hero", "crew"]
      assert page["values"]["hero"] == %{"title" => "Page hero"}

      assert "/about" in Enum.map(routes, & &1["path"])
      assert assets == ["/assets/logo.png"]
    end

    test "a post route has no page settings to edit", %{dir: dir} do
      state = dir |> request(:get, "/__preview/state?path=/posts/hello") |> json()
      assert state["page"] == nil
    end

    test "posting settings writes the file, and the next render reflects them", %{dir: dir} do
      payload = %{
        tokens: %{
          "accent" => "#ff0000",
          "hero" => %{"title" => "Edited hero"},
          "links" => [
            %{"_id" => 1, "label" => "Docs", "url" => "/docs"},
            %{"_id" => 2, "label" => "Blog", "url" => ""}
          ]
        },
        page: %{
          slug: "home",
          metadata: %{
            "hero" => %{"title" => "Edited page"},
            "crew" => [%{"_id" => 3, "name" => "Ada"}]
          }
        }
      }

      assert request(dir, :post, "/__preview/settings", payload).status == 204

      # Persisted and canonicalized: no editor `_id`s, no empty subvalues.
      stored = dir |> Settings.path() |> File.read!() |> Jason.decode!()

      assert stored["tokens"]["hero"] == %{"title" => "Edited hero"}

      assert stored["tokens"]["links"] == [
               %{"label" => "Docs", "url" => "/docs"},
               %{"label" => "Blog"}
             ]

      assert stored["pages"]["home"]["metadata"]["crew"] == [%{"name" => "Ada"}]
      refute stored |> Jason.encode!() |> String.contains?("_id")

      # And the theme renders them — the whole point of the round-trip.
      home = request(dir, :get, "/").resp_body
      assert home =~ "--accent: #ff0000;"
      assert home =~ ~s(data-title="Edited page")
      assert home =~ "<span>Ada</span>"

      about = request(dir, :get, "/about").resp_body
      assert about =~ ~s(data-hero="Edited hero")
      assert about =~ "<li>Docs|/docs</li>"
      # The item whose `url` was blanked falls back to the field's default.
      assert about =~ "<li>Blog|/</li>"
    end

    test "reset drops every local edit", %{dir: dir} do
      request(dir, :post, "/__preview/settings", %{tokens: %{"accent" => "#ff0000"}})
      assert File.exists?(Settings.path(dir))

      assert request(dir, :post, "/__preview/reset").status == 204
      refute File.exists?(Settings.path(dir))
      assert request(dir, :get, "/").resp_body =~ "--accent: #0066cc;"
    end

    test "with --no-editor there is no editor to reach", %{dir: dir} do
      conn =
        Router.call(conn(:get, "/__preview"), Router.init(dir: dir, editor: false, log: false))

      # It falls through to the theme, which has no such page.
      assert conn.status == 404
    end
  end
end
