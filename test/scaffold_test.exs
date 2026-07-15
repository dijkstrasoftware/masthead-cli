defmodule MastheadCli.ScaffoldTest do
  use ExUnit.Case, async: true

  alias MastheadCli.Scaffold

  describe "slugify/1" do
    test "lowercases and hyphenates" do
      assert Scaffold.slugify("My Theme") == "my-theme"
      assert Scaffold.slugify("My_Cool Theme!") == "my-cool-theme"
    end

    test "trims leading/trailing separators" do
      assert Scaffold.slugify("  -Hello-  ") == "hello"
      assert Scaffold.slugify("!!!") == ""
    end

    test "caps length at 32 chars" do
      slug = Scaffold.slugify(String.duplicate("a", 50))
      assert String.length(slug) == 32
    end
  end

  describe "titleize/1" do
    test "turns a slug into a human title" do
      assert Scaffold.titleize("my-blog") == "My Blog"
      assert Scaffold.titleize("acme") == "Acme"
    end
  end

  describe "personalize_manifest/3" do
    @manifest """
    {
      "name": "Default",
      "slug": "upload",
      "version": "1.1.0",
      "tokens": [
        {"key": "accent", "label": "Accent", "type": "color", "default": "#0066cc"}
      ]
    }
    """

    test "rewrites only the top-level name and slug" do
      out = Scaffold.personalize_manifest(@manifest, "My Blog", "my-blog")

      assert {:ok, decoded} = Jason.decode(out)
      assert decoded["name"] == "My Blog"
      assert decoded["slug"] == "my-blog"
      # version and nested token keys are untouched
      assert decoded["version"] == "1.1.0"
      assert [%{"key" => "accent"}] = decoded["tokens"]
    end

    test "escapes JSON-special characters in the name" do
      out = Scaffold.personalize_manifest(@manifest, ~s(A "quoted" name), "x")
      assert {:ok, decoded} = Jason.decode(out)
      assert decoded["name"] == ~s(A "quoted" name)
    end
  end
end
