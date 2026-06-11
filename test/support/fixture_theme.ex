defmodule MastheadCli.FixtureTheme do
  @moduledoc """
  Writes a minimal but complete theme to a temp directory for tests, and
  loads it via `MastheadCli.Theme`. The templates deliberately exercise
  the variable contract: site fields, theme tokens, the injected CSS,
  posts/pages loops, page metadata, and the `asset_url`/`strftime`
  filters.
  """

  alias MastheadCli.Theme

  @manifest """
  {
    "name": "Test Theme",
    "slug": "test-theme",
    "version": "1.0.0",
    "author": "Tests",
    "description": "A theme used by the masthead_cli test suite.",
    "tokens": [
      {"key": "accent", "label": "Accent", "type": "color", "default": "#0066cc"},
      {"key": "max_width", "label": "Width", "type": "length", "default": "880px"},
      {"key": "logo", "label": "Logo", "type": "file", "default": ""}
    ],
    "metadata": [
      {"key": "layout", "label": "Layout", "type": "select", "options": ["contained", "wide"], "default": "contained"},
      {"key": "show_navigation", "label": "Nav", "type": "boolean", "default": true}
    ]
  }
  """

  @css "body { color: var(--accent); max-width: var(--max-width); }"

  @layout """
  <!DOCTYPE html>
  <html>
  <head>
  <title>{{ site.title | default: site.name | escape }}</title>
  <style>{{ theme.css }}{{ site.css_overrides }}</style>
  <link rel="icon" href="{{ 'favicon.ico' | asset_url: theme.asset_base }}" />
  </head>
  <body class="{% if page.metadata.layout == 'wide' %}wide{% endif %}">
  {% unless page.metadata.show_navigation == false %}
  <nav>{% for p in pages %}<a href="{{ p.url }}">{{ p.title | escape }}</a>{% endfor %}</nav>
  {% endunless %}
  <main>{{ content }}</main>
  </body>
  </html>
  """

  @index """
  <h1>{{ site.name | escape }}</h1>
  <ul class="posts">
  {% for post in posts %}<li><a href="{{ post.url }}">{{ post.title | escape }}</a> — {{ post.published_at | strftime: "%Y" }}</li>{% endfor %}
  </ul>
  """

  @post """
  <article><h1>{{ post.title | escape }}</h1>{{ body_html }}</article>
  """

  @page """
  <article class="page"><h1>{{ page.title | escape }}</h1>{{ body_html }}</article>
  """

  @blog """
  <section class="blog">{{ body_html }}<ul>{% for post in posts %}<li>{{ post.title | escape }}</li>{% endfor %}</ul></section>
  """

  @not_found """
  <h1>Not found</h1><p>{{ site.name | escape }}</p>
  """

  @files %{
    "manifest.json" => @manifest,
    "theme.css" => @css,
    "templates/layout.liquid" => @layout,
    "templates/index.liquid" => @index,
    "templates/post.liquid" => @post,
    "templates/page.liquid" => @page,
    "templates/blog.liquid" => @blog,
    "templates/not_found.liquid" => @not_found
  }

  @doc "Create the fixture theme under a fresh temp dir and return the path."
  def create!(overrides \\ %{}) do
    dir = Path.join(System.tmp_dir!(), "masthead_cli_test_#{System.unique_integer([:positive])}")
    files = Map.merge(@files, overrides)

    Enum.each(files, fn {rel, contents} ->
      path = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end)

    dir
  end

  @doc "Create the fixture theme and load it. Returns `{dir, theme}`."
  def load!(overrides \\ %{}) do
    dir = create!(overrides)
    {:ok, theme} = Theme.load(dir)
    {dir, theme}
  end
end
