defmodule MastheadCli.RendererTest do
  use ExUnit.Case, async: true

  alias MastheadCli.{Content, FixtureTheme, Renderer}

  setup do
    {dir, theme} = FixtureTheme.load!()
    on_exit(fn -> File.rm_rf!(dir) end)

    site = %{
      name: "Acme",
      title: "Acme Co.",
      description: "We make things",
      slug: "acme",
      css_overrides: "",
      homepage_slug: nil,
      theme_tokens: %{}
    }

    %{theme: theme, site: site}
  end

  test "renders a theme page with object + list defaults from its sidecar config", %{site: site} do
    {dir, theme} =
      FixtureTheme.load!(%{
        "templates/pages/home.liquid" =>
          ~s(<h1>{{ page.metadata.hero.title | escape }}</h1>) <>
            "{% for f in page.metadata.features %}<li>{{ f.name | escape }}</li>{% endfor %}",
        "templates/pages/home.json" =>
          ~s({"metadata":[) <>
            ~s({"key":"hero","label":"Hero","type":"object","fields":[{"key":"title","label":"T","type":"string","default":"Welcome"}]},) <>
            ~s({"key":"features","label":"F","type":"list","fields":[{"key":"name","label":"N","type":"string","default":""}],) <>
            ~s("default":[{"name":"Fast"},{"name":"Simple"}]}]})
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    page = %{title: "Home", slug: "home", format: "theme", template: "home", metadata: %{}}
    html = Renderer.render_theme_page(theme, %{site: site, page: page, posts: [], pages: []})

    assert html =~ "<h1>Welcome</h1>"
    assert html =~ "<li>Fast</li>"
    assert html =~ "<li>Simple</li>"
  end

  test "a theme page with a missing template falls back to the page template", %{
    theme: theme,
    site: site
  } do
    page = %{
      title: "Gone",
      slug: "gone",
      format: "theme",
      template: "does-not-exist",
      metadata: %{}
    }

    html = Renderer.render_theme_page(theme, %{site: site, page: page, posts: [], pages: []})
    # The fixture's page template renders the title; no crash.
    assert html =~ "Gone"
  end

  test "index injects token defaults as a :root cascade", %{theme: theme, site: site} do
    html = Renderer.render_index(theme, %{site: site, posts: [], pages: []})

    assert html =~ "--accent: #0066cc;"
    assert html =~ "--max-width: 880px;"
    # The `logo` file token is empty and must NOT emit a declaration.
    refute html =~ "--logo:"
  end

  test "token overrides win over defaults", %{theme: theme, site: site} do
    site = %{site | theme_tokens: %{"accent" => "#ff0000"}}
    html = Renderer.render_index(theme, %{site: site, posts: [], pages: []})
    assert html =~ "--accent: #ff0000;"
    refute html =~ "--accent: #0066cc;"
  end

  test "a populated file token is wrapped in url()", %{theme: theme, site: site} do
    site = %{site | theme_tokens: %{"logo" => "/assets/logo.png"}}
    html = Renderer.render_index(theme, %{site: site, posts: [], pages: []})
    assert html =~ "--logo: url(/assets/logo.png);"
  end

  test "renders posts in the index loop with strftime", %{theme: theme, site: site} do
    posts = [
      %{
        title: "Hello",
        slug: "hello",
        excerpt: "",
        format: "markdown",
        body: "",
        published_at: ~U[2026-01-02 10:00:00Z]
      }
    ]

    html = Renderer.render_index(theme, %{site: site, posts: posts, pages: []})
    assert html =~ ~s(<a href="/posts/hello">Hello</a> — 2026)
  end

  test "renders a markdown post body through the content pipeline", %{theme: theme, site: site} do
    post = %{
      title: "P",
      slug: "p",
      excerpt: "",
      format: "markdown",
      published_at: ~U[2026-01-02 10:00:00Z],
      body: "## Heading\n\n**bold**"
    }

    body_html = Content.render_body(post.body, post.format)
    html = Renderer.render_post(theme, %{site: site, post: post, body_html: body_html, pages: []})

    assert html =~ "Heading</h2>"
    assert html =~ "<strong>bold</strong>"
    assert html =~ "<title>Acme Co.</title>"
  end

  test "page metadata merges manifest defaults", %{theme: theme, site: site} do
    # No override -> default layout "contained" -> body has no `wide` class.
    page = %{
      title: "About",
      slug: "about",
      format: "markdown",
      show_in_nav: true,
      metadata: %{},
      body: "hi"
    }

    html = Renderer.render_page(theme, %{site: site, page: page, body_html: "hi", pages: []})
    assert html =~ ~s(<body class="">)

    # Override layout=wide -> body carries the `wide` class.
    page = %{page | metadata: %{"layout" => "wide"}}
    html = Renderer.render_page(theme, %{site: site, page: page, body_html: "hi", pages: []})
    assert html =~ ~s(<body class="wide">)
  end

  test "show_navigation=false hides the nav on that page", %{theme: theme, site: site} do
    pages_for_nav = [
      %{title: "About", slug: "about", format: "markdown", metadata: %{}, show_in_nav: true}
    ]

    page = %{
      title: "Solo",
      slug: "solo",
      format: "markdown",
      show_in_nav: true,
      metadata: %{"show_navigation" => false},
      body: "x"
    }

    html =
      Renderer.render_page(theme, %{site: site, page: page, body_html: "x", pages: pages_for_nav})

    refute html =~ "<nav>"
  end

  test "asset_url uses the /assets base", %{theme: theme, site: site} do
    html = Renderer.render_index(theme, %{site: site, posts: [], pages: []})
    assert html =~ ~s(<link rel="icon" href="/assets/favicon.ico" />)
  end

  test "css_overrides are sanitized then appended", %{theme: theme, site: site} do
    site = %{site | css_overrides: ".x { color: red; } </style><script>evil()"}
    html = Renderer.render_index(theme, %{site: site, posts: [], pages: []})
    assert html =~ ".x { color: red; }"
    refute html =~ "<script>evil"
    refute html =~ "</style><script>"
  end

  describe "tags" do
    setup do
      posts = [post("Doom config", "doom", ["Emacs"]), post("Off topic", "off-topic", [])]
      {:ok, posts: posts, tags: [%{name: "Emacs", slug: "emacs"}]}
    end

    test "tags and current_tag reach the template", %{site: site, posts: posts, tags: tags} do
      {dir, theme} =
        FixtureTheme.load!(%{
          "templates/index.liquid" =>
            ~s(<ul>{% for t in tags %}<li data-active="{{ t.active }}">{{ t.name }}</li>{% endfor %}</ul>) <>
              ~s(<p>{{ current_tag.slug }}</p>)
        })

      on_exit(fn -> File.rm_rf!(dir) end)

      html =
        Renderer.render_index(theme, %{
          site: site,
          posts: posts,
          pages: [],
          tags: tags,
          current_tag: %{name: "Emacs", slug: "emacs"}
        })

      assert html =~ ~s(<li data-active="true">Emacs</li>)
      assert html =~ "<p>emacs</p>"
    end

    test "posts_by_tag and where_tag both select the tagged posts", %{
      site: site,
      posts: posts,
      tags: tags
    } do
      {dir, theme} =
        FixtureTheme.load!(%{
          "templates/index.liquid" => """
          {% assign tagged = posts_by_tag["emacs"] %}
          <ul>{% for p in tagged %}<li>BY_TAG {{ p.title }}</li>{% endfor %}</ul>
          {% assign filtered = posts | where_tag: "emacs" %}
          <ul>{% for p in filtered %}<li>FILTER {{ p.title }}</li>{% endfor %}</ul>
          """
        })

      on_exit(fn -> File.rm_rf!(dir) end)

      html =
        Renderer.render_index(theme, %{
          site: site,
          posts: posts,
          all_posts: posts,
          pages: [],
          tags: tags
        })

      assert html =~ "BY_TAG Doom config"
      refute html =~ "BY_TAG Off topic"
      assert html =~ "FILTER Doom config"
      refute html =~ "FILTER Off topic"
    end
  end

  test "search exposes the query and the match count", %{site: site} do
    {dir, theme} =
      FixtureTheme.load!(%{
        "templates/index.liquid" =>
          ~s(<p>{{ search_query }} / {{ search_count }}</p>) <>
            ~s({% unless search_query %}<p>no query</p>{% endunless %})
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    hit = post("Doom config", "doom", [])
    html = Renderer.render_search(theme, %{site: site, posts: [hit], pages: [], query: "doom"})
    assert html =~ "<p>doom / 1</p>"

    # A blank query normalises to nil — an empty string is truthy in Liquid, so a
    # theme could never branch on it otherwise.
    blank = Renderer.render_search(theme, %{site: site, posts: [], pages: [], query: "  "})
    assert blank =~ "no query"
  end

  defp post(title, slug, tags) do
    %{
      title: title,
      slug: slug,
      excerpt: "",
      format: "markdown",
      body: "",
      published_at: ~U[2026-01-02 10:00:00Z],
      tags: Enum.map(tags, &%{name: &1, slug: String.downcase(&1)})
    }
  end
end
