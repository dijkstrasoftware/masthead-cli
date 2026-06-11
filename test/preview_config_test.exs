defmodule MastheadCli.PreviewConfigTest do
  use ExUnit.Case, async: true

  alias MastheadCli.{FixtureTheme, PreviewConfig}

  test "with no overrides, returns the built-in sample content" do
    dir = FixtureTheme.create!()
    on_exit(fn -> File.rm_rf!(dir) end)

    %{site: site, posts: posts, pages: pages} = PreviewConfig.load(dir)
    assert site.name == "The Long Way Round"
    assert length(posts) == 3
    assert Enum.any?(pages, &(&1.slug == "about"))
  end

  test "preview.json overrides site fields, tokens and homepage" do
    json = ~s({
      "site": {"name": "Acme", "title": "Acme Co.", "homepage": "home"},
      "tokens": {"accent": "#ff0000"}
    })

    dir = FixtureTheme.create!(%{"preview.json" => json})
    on_exit(fn -> File.rm_rf!(dir) end)

    %{site: site} = PreviewConfig.load(dir)
    assert site.name == "Acme"
    assert site.title == "Acme Co."
    assert site.homepage_slug == "home"
    assert site.theme_tokens == %{"accent" => "#ff0000"}
  end

  test "markdown files with JSON front matter become posts, newest first" do
    older = """
    ---
    {"title": "Older", "slug": "older", "published_at": "2026-01-01"}
    ---
    body one
    """

    newer = """
    ---
    {"title": "Newer", "slug": "newer", "published_at": "2026-02-01"}
    ---
    body two
    """

    dir =
      FixtureTheme.create!(%{
        "preview/posts/a.md" => older,
        "preview/posts/b.md" => newer
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    %{posts: posts} = PreviewConfig.load(dir)
    assert Enum.map(posts, & &1.slug) == ["newer", "older"]
    assert hd(posts).body =~ "body two"
  end

  test "pages from files sort by title and honor front matter" do
    dir =
      FixtureTheme.create!(%{
        "preview/pages/z.md" => ~s(---\n{"title":"Zeta","slug":"zeta"}\n---\nz),
        "preview/pages/a.md" =>
          ~s(---\n{"title":"Alpha","slug":"alpha","metadata":{"layout":"wide"}}\n---\na)
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    %{pages: pages} = PreviewConfig.load(dir)
    assert Enum.map(pages, & &1.title) == ["Alpha", "Zeta"]
    assert hd(pages).metadata == %{"layout" => "wide"}
  end

  test "split_front_matter handles files without front matter" do
    assert {%{}, "just body\n"} = PreviewConfig.split_front_matter("just body\n")
  end
end
