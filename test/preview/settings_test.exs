defmodule MastheadCli.Preview.SettingsTest do
  use ExUnit.Case, async: true

  alias MastheadCli.Manifest
  alias MastheadCli.Preview.Settings
  alias MastheadCli.PreviewConfig

  @fields_json """
  {
    "name": "T", "slug": "t", "version": "1.0.0",
    "tokens": [
      {"key": "accent", "label": "Accent", "type": "color", "default": "#000"},
      {"key": "hero", "label": "Hero", "type": "object", "fields": [
        {"key": "title", "label": "Title", "type": "string", "default": ""},
        {"key": "lede", "label": "Lede", "type": "string", "default": ""}
      ]},
      {"key": "links", "label": "Links", "type": "list", "fields": [
        {"key": "label", "label": "Label", "type": "string", "default": ""}
      ]}
    ]
  }
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "mh_settings_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, manifest} = Manifest.parse(@fields_json)
    {:ok, dir: dir, fields: manifest.tokens}
  end

  test "an absent (or unreadable) file reads as empty", %{dir: dir} do
    assert Settings.load(dir) == %{tokens: %{}, pages: %{}}

    File.write!(Settings.path(dir), "{ not json")
    assert Settings.load(dir) == %{tokens: %{}, pages: %{}}
  end

  test "tokens round-trip, canonicalized", %{dir: dir, fields: fields} do
    Settings.put_tokens(
      dir,
      %{
        "accent" => "#ff0000",
        "hero" => %{"title" => "Hi", "lede" => ""},
        "links" => [%{"_id" => 7, "label" => "Docs"}, %{"_id" => 8, "label" => ""}]
      },
      fields
    )

    %{tokens: tokens} = Settings.load(dir)

    assert tokens["accent"] == "#ff0000"
    # An empty subvalue is dropped (the renderer fills the field's default), and
    # the editor's `_id`s never reach the file.
    assert tokens["hero"] == %{"title" => "Hi"}
    # An empty list *item* is kept — its count and order are meaningful.
    assert tokens["links"] == [%{"label" => "Docs"}, %{}]
  end

  test "a page's metadata is stored under its slug", %{dir: dir, fields: fields} do
    Settings.put_page_metadata(dir, "home", %{"hero" => %{"title" => "Home"}}, fields)
    settings = Settings.load(dir)

    assert Settings.page_metadata(settings, "home") == %{"hero" => %{"title" => "Home"}}
    assert Settings.page_metadata(settings, "other") == %{}
  end

  test "reset removes the file, and is fine when there isn't one", %{dir: dir, fields: fields} do
    Settings.put_tokens(dir, %{"accent" => "#fff"}, fields)
    assert File.exists?(Settings.path(dir))

    assert Settings.reset(dir) == :ok
    refute File.exists?(Settings.path(dir))
    assert Settings.reset(dir) == :ok
  end

  test "it is added to .gitignore, once", %{dir: dir} do
    assert Settings.ensure_gitignored(dir) == :added
    assert File.read!(Path.join(dir, ".gitignore")) =~ "preview.local.json"

    assert Settings.ensure_gitignored(dir) == :present
    entries = dir |> Path.join(".gitignore") |> File.read!() |> String.split("\n", trim: true)
    assert Enum.count(entries, &(&1 == "preview.local.json")) == 1
  end

  test "it layers over preview.json without rewriting it", %{dir: dir, fields: fields} do
    preview_json = """
    {
      "site": {"name": "Seeded"},
      "tokens": {"accent": "#111111", "hero": {"title": "Seeded hero"}},
      "pages": [{"title": "Home", "slug": "home", "format": "theme", "template": "home",
                 "metadata": {"layout": "wide"}}]
    }
    """

    File.write!(Path.join(dir, "preview.json"), preview_json)

    Settings.put_tokens(dir, %{"accent" => "#222222"}, fields)
    Settings.put_page_metadata(dir, "home", %{"hero" => %{"title" => "Edited"}}, [])

    data = PreviewConfig.load(dir)

    # The sidebar's value wins; the seed's other keys survive.
    assert data.site.theme_tokens["accent"] == "#222222"
    assert data.site.theme_tokens["hero"] == %{"title" => "Seeded hero"}

    page = Enum.find(data.pages, &(&1.slug == "home"))
    assert page.metadata["hero"] == %{"title" => "Edited"}
    assert page.metadata["layout"] == "wide"

    # The hand-authored seed is never touched.
    assert File.read!(Path.join(dir, "preview.json")) == preview_json
  end

  test "preview.json's tokens keep their shape (no flattening to strings)", %{dir: dir} do
    File.write!(Path.join(dir, "preview.json"), """
    {"tokens": {"links": [{"label": "Docs"}], "show": true}}
    """)

    tokens = PreviewConfig.load(dir).site.theme_tokens

    assert tokens["links"] == [%{"label" => "Docs"}]
    assert tokens["show"] == true
  end
end
