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
end
