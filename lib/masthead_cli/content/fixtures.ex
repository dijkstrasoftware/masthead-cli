defmodule MastheadCli.Content.Fixtures do
  @moduledoc """
  Built-in sample content used by `masthead preview` when the theme
  directory has no `preview/` overrides. Gives every theme a realistic
  site, a few posts and a couple of pages to render against with zero
  configuration.

  All shapes match what `MastheadCli.PreviewConfig` produces and what
  `MastheadCli.Presenter` expects (atom-keyed maps).
  """

  @doc "The default preview dataset: `%{site: ..., posts: [...], pages: [...]}`."
  def default do
    %{
      site: default_site(),
      posts: default_posts(),
      pages: default_pages()
    }
  end

  def default_site do
    %{
      name: "The Long Way Round",
      title: "The Long Way Round",
      description:
        "Notes on building software slowly, on purpose — craft, tools, and the occasional detour.",
      slug: "preview",
      css_overrides: "",
      # Set via preview.json `site.homepage`; nil means the theme's own
      # index template (post list) is rendered at `/`.
      homepage_slug: nil,
      # Token overrides (merged over manifest defaults). Empty by default so
      # the theme shows itself exactly as authored.
      theme_tokens: %{}
    }
  end

  def default_posts do
    [
      %{
        title: "On Choosing Boring Technology",
        slug: "boring-technology",
        excerpt:
          "The most exciting decision you can make is usually the most boring one. A short defense of dependable tools.",
        format: "markdown",
        published_at: days_ago(2),
        body: """
        Every project starts with the same temptation: reach for the newest,
        shiniest thing. Resist it.

        ## Innovation tokens

        You get a small number of *innovation tokens*. Spend them where they
        matter — the actual problem you're solving — and use boring,
        well-understood technology everywhere else.

        - A database you've run in production before.
        - A language your team already knows.
        - A deployment story you can debug at 3am.

        > The best tool is the one whose failure modes you already understand.

        Boring isn't a synonym for bad. It's a synonym for *known*.

        ### A quick checklist

        1. Has this survived a few years of real use?
        2. Can you find answers when it breaks?
        3. Would you bet a weekend on it?

        If the answer to all three is yes, you've probably found the right
        tool — even if nobody will be impressed at the conference.
        """
      },
      %{
        title: "The Underrated Power of Plain Text",
        slug: "plain-text",
        excerpt:
          "Files you can read in fifty years, grep in a second, and version with git. Plain text is quietly the best format we have.",
        format: "markdown",
        published_at: days_ago(9),
        body: """
        There's a reason the tools that last are the ones built on plain
        text. Markdown, CSV, config files, source code — all just text.

        ## Why it wins

        Plain text is **diffable**, **greppable**, and **durable**. It
        outlives the application that created it. Open a `.txt` file from
        1995 and it still renders perfectly today.

        ```elixir
        defmodule Notes do
          def read!(path), do: File.read!(path)
        end
        ```

        Compare that to a proprietary binary blob whose only reader stopped
        shipping a decade ago.

        Keep your important things in text. Future-you will be grateful.
        """
      },
      %{
        title: "Small Tools, Composed",
        slug: "small-tools-composed",
        excerpt:
          "The Unix idea that refuses to die: do one thing well, and let things talk to each other.",
        format: "markdown",
        published_at: days_ago(21),
        body: """
        A big monolithic tool tries to anticipate every need and fails at
        the edges. A small tool does one thing and gets out of the way.

        The magic is in *composition*: when each piece reads from one place
        and writes to another, you can chain them into something nobody
        designed up front.

        - Easy to test, because the surface is small.
        - Easy to replace, because the boundaries are clear.
        - Easy to reason about, because there's less to hold in your head.

        Build the small thing. Let it compose.
        """
      }
    ]
  end

  def default_pages do
    [
      %{
        title: "About",
        slug: "about",
        format: "markdown",
        show_in_nav: true,
        metadata: %{},
        body: """
        ## About this site

        This is sample content rendered by **masthead preview** so you can
        see your theme with realistic copy — headings, lists, links,
        `inline code`, and the occasional [link](https://masthead.site).

        Replace it with your own by dropping a `preview/` folder into your
        theme directory. Until then, edit away and refresh — your CSS and
        template changes show up immediately.
        """
      },
      %{
        title: "Blog",
        slug: "blog",
        format: "theme",
        template: "blog",
        show_in_nav: true,
        metadata: %{},
        body: ""
      }
    ]
  end

  # Preview timestamps are relative to "now" so dates always look fresh.
  defp days_ago(n) do
    DateTime.utc_now()
    |> DateTime.add(-n * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
  end
end
