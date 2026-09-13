defmodule MastheadCli.Content.Fixtures do
  @moduledoc """
  Built-in sample content used by `masthead preview` when the theme
  directory has no `preview/` overrides. Gives every theme a few posts and
  pages to render against with zero configuration.

  The copy is lorem ipsum on purpose: filler reads as filler, so nothing here
  can be mistaken for the author's own content, and the eye judges the layout
  rather than the words. The *shape* is deliberate, though — headings, lists,
  a blockquote, a code block, inline formatting and links — so a theme's CSS
  gets exercised the way real content would exercise it.

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
      name: "Lorem Ipsum",
      title: "Lorem Ipsum Dolor",
      description: "Sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt.",
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
        title: "Lorem ipsum dolor sit amet",
        slug: "lorem-ipsum-dolor-sit-amet",
        excerpt:
          "Consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
        format: "markdown",
        published_at: days_ago(2),
        tags: [tag("Lorem"), tag("Ipsum")],
        post_options: %{},
        body: """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
        tempor incididunt ut labore et dolore magna aliqua.

        ## Ut enim ad minim veniam

        Quis nostrud exercitation ullamco laboris nisi ut *aliquip* ex ea
        commodo consequat. Duis aute irure dolor in reprehenderit in voluptate
        velit esse cillum dolore.

        - Excepteur sint occaecat cupidatat non proident.
        - Sunt in culpa qui officia deserunt mollit.
        - Anim id est laborum et dolorum fuga.

        > Sed ut perspiciatis unde omnis iste natus error sit voluptatem
        > accusantium doloremque laudantium.

        Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut
        fugit, sed quia consequuntur magni dolores eos.

        ### Neque porro quisquam est

        1. Qui dolorem ipsum quia dolor sit amet.
        2. Consectetur, adipisci velit, sed quia non numquam.
        3. Eius modi tempora incidunt ut labore et dolore.

        Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis
        suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur.
        """
      },
      %{
        title: "Sed ut perspiciatis unde omnis",
        slug: "sed-ut-perspiciatis",
        excerpt:
          "Iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam.",
        format: "markdown",
        published_at: days_ago(9),
        tags: [tag("Lorem"), tag("Dolor")],
        post_options: %{},
        body: """
        At vero eos et accusamus et iusto odio dignissimos ducimus qui
        blanditiis praesentium voluptatum deleniti atque corrupti.

        ## Quos dolores et quas molestias

        Excepturi sint occaecati cupiditate non provident, **similique sunt**
        in culpa qui officia deserunt mollitia animi, id est laborum et
        dolorum fuga. Et harum quidem rerum facilis est et `expedita`
        distinctio.

        ```elixir
        defmodule Lorem do
          def ipsum(dolor), do: "sit amet, " <> dolor
        end
        ```

        Nam libero tempore, cum soluta nobis est eligendi optio cumque nihil
        impedit quo minus id quod maxime placeat facere possimus, omnis
        voluptas assumenda est, omnis dolor [repellendus](https://example.com).
        """
      },
      %{
        title: "Temporibus autem quibusdam",
        slug: "temporibus-autem-quibusdam",
        excerpt:
          "Et aut officiis debitis aut rerum necessitatibus saepe eveniet ut et voluptates.",
        format: "markdown",
        published_at: days_ago(21),
        tags: [tag("Ipsum")],
        post_options: %{},
        body: """
        Repudiandae sint et molestiae non recusandae. Itaque earum rerum hic
        tenetur a sapiente delectus.

        Ut aut reiciendis voluptatibus maiores alias consequatur aut
        perferendis doloribus asperiores repellat.

        - Lorem ipsum dolor sit amet, consectetur.
        - Adipiscing elit, sed do eiusmod tempor.
        - Incididunt ut labore et dolore magna.

        Aliqua ut enim ad minim veniam, quis nostrud exercitation.
        """
      }
    ]
  end

  def default_pages do
    [
      %{
        title: "Lorem",
        slug: "lorem",
        format: "markdown",
        show_in_nav: true,
        page_options: %{},
        body: """
        ## Dolor sit amet

        Consectetur adipiscing elit, sed do eiusmod tempor incididunt ut
        labore et dolore magna aliqua — headings, lists, links,
        `inline code`, and the occasional [link](https://masthead.site).

        Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris
        nisi ut aliquip ex ea commodo consequat.
        """
      },
      %{
        title: "Ipsum",
        slug: "ipsum",
        format: "theme",
        template: "blog",
        show_in_nav: true,
        page_options: %{},
        body: ""
      }
    ]
  end

  # A tag, slugged the way the platform slugs it.
  defp tag(name) do
    %{name: name, slug: name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")}
  end

  # Preview timestamps are relative to "now" so dates always look fresh.
  defp days_ago(n) do
    DateTime.utc_now()
    |> DateTime.add(-n * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
  end
end
